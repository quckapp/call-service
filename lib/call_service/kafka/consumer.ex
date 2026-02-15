defmodule CallService.Kafka.Consumer do
  @moduledoc """
  Kafka consumer for call-related events from other services.

  ## Design Patterns Used:
  - **Circuit Breaker**: Graceful degradation when Kafka is unavailable
  - **Strategy Pattern**: Event handlers for different event types
  - **Command Pattern**: Async event processing via Task
  - **Observer Pattern**: PubSub notifications for call events

  ## Data Structures:
  - MapSet for tracking processed message IDs (deduplication)
  - ETS table for circuit breaker state and caching
  - Queue (via GenServer state) for retry buffer
  """
  use GenServer
  require Logger

  # Valid call states - prevents atom table exhaustion
  @valid_call_states ~w(initiating ringing answered rejected busy ended missed)
  @valid_call_types ~w(audio video screen_share)

  # Circuit breaker configuration
  @max_failures 5
  @reset_timeout_ms 30_000
  @retry_delay_ms 5_000

  # Deduplication window
  @dedup_window_ms 60_000

  # Topics
  @topics ["call-events", "user-presence", "signaling-events"]

  defstruct [
    :consumer_pid,
    :brokers,
    :group_id,
    :topics,
    :circuit_state,
    :failure_count,
    :last_failure_at,
    :retry_buffer,
    enabled: false
  ]

  # ============================================================================
  # Public API
  # ============================================================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Check if consumer is healthy"
  def healthy? do
    GenServer.call(__MODULE__, :health_check)
  catch
    :exit, _ -> false
  end

  @doc "Get consumer statistics"
  def stats do
    GenServer.call(__MODULE__, :stats)
  catch
    :exit, _ -> %{status: :unavailable}
  end

  @doc "Get circuit breaker state"
  def circuit_state do
    GenServer.call(__MODULE__, :circuit_state)
  catch
    :exit, _ -> :unknown
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl true
  def init(_opts) do
    # Initialize ETS for deduplication
    :ets.new(:call_kafka_dedup, [:set, :named_table, :public])

    config = Application.get_env(:call_service, :kafka, [])
    enabled = config[:enabled] || System.get_env("KAFKA_ENABLED") == "true"

    state = %__MODULE__{
      circuit_state: :closed,
      failure_count: 0,
      last_failure_at: nil,
      retry_buffer: :queue.new(),
      enabled: enabled
    }

    if enabled do
      # Schedule initial connection attempt
      send(self(), :connect)
    else
      Logger.info("[CallKafkaConsumer] Kafka disabled - running without event streaming")
    end

    # Schedule periodic cleanup
    schedule_cleanup()

    {:ok, state}
  end

  @impl true
  def handle_info(:connect, %{enabled: false} = state) do
    {:noreply, state}
  end

  @impl true
  def handle_info(:connect, state) do
    case connect_to_kafka(state) do
      {:ok, new_state} ->
        Logger.info("[CallKafkaConsumer] Successfully connected to Kafka")
        {:noreply, %{new_state | circuit_state: :closed, failure_count: 0}}

      {:error, reason} ->
        new_state = handle_connection_failure(state, reason)
        {:noreply, new_state}
    end
  end

  @impl true
  def handle_info(:retry_connect, state) do
    if state.circuit_state == :open do
      if should_attempt_reset?(state) do
        Logger.info("[CallKafkaConsumer] Circuit half-open, attempting reconnect")
        send(self(), :connect)
        {:noreply, %{state | circuit_state: :half_open}}
      else
        schedule_retry()
        {:noreply, state}
      end
    else
      send(self(), :connect)
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(:cleanup_dedup, state) do
    cutoff = System.system_time(:millisecond) - @dedup_window_ms

    :ets.select_delete(:call_kafka_dedup, [
      {{:"$1", :"$2"}, [{:<, :"$2", cutoff}], [true]}
    ])

    schedule_cleanup()
    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, %{consumer_pid: pid} = state) do
    Logger.warning("[CallKafkaConsumer] Consumer process died: #{inspect(reason)}")
    new_state = handle_connection_failure(state, reason)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def handle_call(:health_check, _from, state) do
    healthy = state.circuit_state == :closed and (state.consumer_pid != nil or not state.enabled)
    {:reply, healthy, state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    stats = %{
      circuit_state: state.circuit_state,
      failure_count: state.failure_count,
      consumer_connected: state.consumer_pid != nil,
      dedup_size: :ets.info(:call_kafka_dedup, :size),
      retry_buffer_size: :queue.len(state.retry_buffer),
      enabled: state.enabled
    }
    {:reply, stats, state}
  end

  @impl true
  def handle_call(:circuit_state, _from, state) do
    {:reply, state.circuit_state, state}
  end

  # ============================================================================
  # Brod Callbacks - Group Subscriber
  # ============================================================================

  @doc "brod_group_subscriber callback - called when subscriber initializes"
  def init(_group_id, _init_args) do
    {:ok, %{}}
  end

  @doc """
  Handles incoming Kafka messages with deduplication and safe processing.
  """
  def handle_message(topic, partition, message, state) do
    message_id = extract_message_id(message)

    cond do
      is_duplicate?(message_id) ->
        Logger.debug("[CallKafkaConsumer] Skipping duplicate message: #{message_id}")
        {:ok, :ack, state}

      true ->
        result = safe_process_message(topic, partition, message)
        mark_processed(message_id)

        case result do
          :ok -> {:ok, :ack, state}
          {:error, :retriable} -> {:ok, :ack_no_commit, state}
          {:error, _} -> {:ok, :ack, state}
        end
    end
  end

  # ============================================================================
  # Private Functions - Connection Management
  # ============================================================================

  defp connect_to_kafka(state) do
    config = Application.get_env(:call_service, :kafka, [])

    brokers = parse_brokers(config[:brokers] || System.get_env("KAFKA_BROKERS") || "localhost:9092")
    group_id = config[:consumer_group] || System.get_env("KAFKA_CONSUMER_GROUP") || "call-service-group"
    client_id = :call_consumer

    Logger.info("[CallKafkaConsumer] Connecting to brokers: #{inspect(brokers)}, group: #{group_id}")

    # Start brod client first (required before starting group subscriber)
    case :brod.start_client(brokers, client_id, []) do
      :ok ->
        start_group_subscriber(state, client_id, brokers, group_id)

      {:error, {:already_started, _pid}} ->
        start_group_subscriber(state, client_id, brokers, group_id)

      {:error, reason} ->
        Logger.error("[CallKafkaConsumer] Failed to start brod client: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp start_group_subscriber(state, client_id, brokers, group_id) do
    group_config = [
      offset_commit_policy: :commit_to_kafka_v2,
      offset_commit_interval_seconds: 5,
      rejoin_delay_seconds: 2
    ]

    consumer_config = [begin_offset: :earliest]

    case :brod.start_link_group_subscriber(
           client_id,
           group_id,
           @topics,
           group_config,
           consumer_config,
           __MODULE__,
           []
         ) do
      {:ok, pid} ->
        Process.monitor(pid)
        {:ok, %{state | consumer_pid: pid, brokers: brokers, group_id: group_id, topics: @topics}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_brokers(brokers) when is_binary(brokers) do
    brokers
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.map(&parse_single_broker/1)
  end

  defp parse_brokers(brokers) when is_list(brokers) do
    Enum.map(brokers, fn
      {host, port} when is_list(host) -> {host, port}
      {host, port} when is_binary(host) -> {String.to_charlist(host), port}
      broker when is_binary(broker) -> parse_single_broker(broker)
    end)
  end

  defp parse_single_broker(broker) do
    case String.split(broker, ":") do
      [host, port] ->
        {String.to_charlist(host), String.to_integer(port)}

      [host] ->
        {String.to_charlist(host), 9092}
    end
  end

  # ============================================================================
  # Private Functions - Circuit Breaker
  # ============================================================================

  defp handle_connection_failure(state, reason) do
    new_failure_count = state.failure_count + 1
    Logger.warning("[CallKafkaConsumer] Connection failed (#{new_failure_count}/#{@max_failures}): #{inspect(reason)}")

    new_state = %{state |
      failure_count: new_failure_count,
      last_failure_at: System.system_time(:millisecond),
      consumer_pid: nil
    }

    if new_failure_count >= @max_failures do
      Logger.error("[CallKafkaConsumer] Circuit breaker OPEN - max failures reached")
      schedule_retry()
      %{new_state | circuit_state: :open}
    else
      schedule_retry()
      new_state
    end
  end

  defp should_attempt_reset?(state) do
    case state.last_failure_at do
      nil -> true
      last_failure ->
        elapsed = System.system_time(:millisecond) - last_failure
        elapsed >= @reset_timeout_ms
    end
  end

  defp schedule_retry do
    Process.send_after(self(), :retry_connect, @retry_delay_ms)
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup_dedup, @dedup_window_ms)
  end

  # ============================================================================
  # Private Functions - Message Processing
  # ============================================================================

  defp safe_process_message(topic, _partition, message) do
    with {:ok, payload} <- extract_payload(message),
         {:ok, event} <- Jason.decode(payload),
         :ok <- process_event(topic, event) do
      :telemetry.execute(
        [:call_service, :kafka, :message_processed],
        %{count: 1},
        %{topic: topic}
      )
      :ok
    else
      {:error, :invalid_json} ->
        Logger.warning("[CallKafkaConsumer] Invalid JSON in message")
        {:error, :invalid_json}

      {:error, :unknown_event} ->
        :ok

      {:error, reason} ->
        Logger.error("[CallKafkaConsumer] Error processing message: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp extract_payload(message) when is_map(message), do: {:ok, message.value}
  defp extract_payload(message) when is_tuple(message), do: {:ok, elem(message, 4)}
  defp extract_payload(_), do: {:error, :invalid_message_format}

  defp extract_message_id(message) do
    case message do
      %{key: key} when is_binary(key) -> key
      %{offset: offset, partition: partition} -> "#{partition}-#{offset}"
      tuple when is_tuple(tuple) -> "#{elem(tuple, 1)}-#{elem(tuple, 2)}"
      _ -> :crypto.strong_rand_bytes(16) |> Base.encode16()
    end
  end

  # ============================================================================
  # Private Functions - Event Handlers (Strategy Pattern)
  # ============================================================================

  defp process_event(_topic, %{"event" => "call_initiated", "call_id" => call_id, "caller_id" => caller_id} = event) do
    callee_id = event["callee_id"]
    call_type = event["call_type"] || "audio"

    with {:ok, type_atom} <- validate_call_type(call_type) do
      Task.start(fn ->
        CallService.CallManager.initiate_call(call_id, caller_id, callee_id, %{
          type: type_atom,
          metadata: event["metadata"] || %{}
        })
      end)
      :ok
    end
  end

  defp process_event(_topic, %{"event" => "call_answered", "call_id" => call_id, "user_id" => user_id}) do
    Task.start(fn ->
      CallService.CallManager.answer_call(call_id, user_id)
    end)
    :ok
  end

  defp process_event(_topic, %{"event" => "call_ended", "call_id" => call_id} = event) do
    reason = event["reason"] || "normal"

    Task.start(fn ->
      CallService.CallManager.end_call(call_id, %{reason: reason})
    end)
    :ok
  end

  defp process_event(_topic, %{"event" => "call_rejected", "call_id" => call_id, "user_id" => user_id}) do
    Task.start(fn ->
      CallService.CallManager.reject_call(call_id, user_id)
    end)
    :ok
  end

  defp process_event(_topic, %{"event" => "user_presence_changed", "user_id" => user_id, "status" => status}) do
    # Update call availability based on presence
    Task.start(fn ->
      CallService.CallManager.update_user_availability(user_id, status)
    end)
    :ok
  end

  defp process_event(_topic, %{"event" => "ice_candidate", "call_id" => call_id} = event) do
    # Forward ICE candidate through signaling
    Task.start(fn ->
      Phoenix.PubSub.broadcast(
        CallService.PubSub,
        "call:#{call_id}",
        {:ice_candidate, event["candidate"], event["from_user"]}
      )
    end)
    :ok
  end

  defp process_event(_topic, %{"event" => event_type} = event) do
    Logger.debug("[CallKafkaConsumer] Unhandled event type: #{event_type}, payload: #{inspect(event)}")
    {:error, :unknown_event}
  end

  defp process_event(_topic, _event) do
    {:error, :unknown_event}
  end

  # ============================================================================
  # Private Functions - Validation
  # ============================================================================

  defp validate_call_type(type) when type in @valid_call_types do
    {:ok, String.to_existing_atom(type)}
  rescue
    ArgumentError -> {:error, :invalid_call_type}
  end

  defp validate_call_type(_type), do: {:error, :invalid_call_type}

  defp validate_call_state(state) when state in @valid_call_states do
    {:ok, String.to_existing_atom(state)}
  rescue
    ArgumentError -> {:error, :invalid_call_state}
  end

  defp validate_call_state(_state), do: {:error, :invalid_call_state}

  # ============================================================================
  # Private Functions - Deduplication
  # ============================================================================

  defp is_duplicate?(message_id) do
    case :ets.lookup(:call_kafka_dedup, message_id) do
      [{^message_id, _timestamp}] -> true
      [] -> false
    end
  end

  defp mark_processed(message_id) do
    timestamp = System.system_time(:millisecond)
    :ets.insert(:call_kafka_dedup, {message_id, timestamp})
  end
end
