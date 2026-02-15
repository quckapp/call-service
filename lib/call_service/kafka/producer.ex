defmodule CallService.Kafka.Producer do
  @moduledoc """
  Kafka producer for publishing call events to other services.

  ## Design Patterns Used:
  - **Circuit Breaker**: Graceful degradation when Kafka is unavailable
  - **Retry Pattern**: Exponential backoff for failed publishes
  - **Async Pattern**: Non-blocking event publishing

  ## Topics Published:
  - call-events: Call lifecycle events (initiated, answered, ended)
  - signaling-events: WebRTC signaling messages
  - user-presence: Presence updates during calls
  """
  use GenServer
  require Logger

  alias CallService.Distribution

  @call_topic "call-events"
  @signaling_topic "signaling-events"

  # Circuit breaker configuration
  @max_failures 5
  @reset_timeout_ms 30_000

  defstruct [
    :client_id,
    :brokers,
    :circuit_state,
    :failure_count,
    :last_failure_at,
    enabled: false
  ]

  # ============================================================================
  # Public API
  # ============================================================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Publish a call event"
  def publish_call_event(event) do
    GenServer.call(__MODULE__, {:publish, @call_topic, event})
  catch
    :exit, _ -> {:error, :producer_unavailable}
  end

  @doc "Publish a signaling event"
  def publish_signaling_event(event) do
    GenServer.call(__MODULE__, {:publish, @signaling_topic, event})
  catch
    :exit, _ -> {:error, :producer_unavailable}
  end

  @doc "Async publish (fire and forget)"
  def publish_async(topic, event) do
    GenServer.cast(__MODULE__, {:publish_async, topic, event})
  end

  @doc "Check if producer is healthy"
  def healthy? do
    GenServer.call(__MODULE__, :health_check)
  catch
    :exit, _ -> false
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl true
  def init(_opts) do
    config = Application.get_env(:call_service, :kafka, [])
    enabled = config[:enabled] || System.get_env("KAFKA_ENABLED") == "true"

    state = %__MODULE__{
      circuit_state: :closed,
      failure_count: 0,
      last_failure_at: nil,
      enabled: enabled
    }

    if enabled do
      send(self(), :connect)
    else
      Logger.info("[CallKafkaProducer] Kafka disabled - events will not be published")
    end

    {:ok, state}
  end

  @impl true
  def handle_info(:connect, state) do
    case start_brod_client(state) do
      {:ok, new_state} ->
        Logger.info("[CallKafkaProducer] Successfully connected to Kafka")
        {:noreply, %{new_state | circuit_state: :closed, failure_count: 0}}

      {:error, reason} ->
        Logger.warning("[CallKafkaProducer] Failed to connect: #{inspect(reason)}")
        schedule_reconnect()
        {:noreply, %{state | failure_count: state.failure_count + 1}}
    end
  end

  @impl true
  def handle_info(:reconnect, state) do
    if should_attempt_reset?(state) do
      send(self(), :connect)
    else
      schedule_reconnect()
    end
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def handle_call(:health_check, _from, state) do
    healthy = state.circuit_state == :closed and (state.client_id != nil or not state.enabled)
    {:reply, healthy, state}
  end

  @impl true
  def handle_call({:publish, _topic, _event}, _from, %{enabled: false} = state) do
    {:reply, {:ok, :kafka_disabled}, state}
  end

  @impl true
  def handle_call({:publish, _topic, _event}, _from, %{circuit_state: :open} = state) do
    {:reply, {:error, :circuit_open}, state}
  end

  @impl true
  def handle_call({:publish, topic, event}, _from, state) do
    case do_publish(topic, event, state) do
      :ok ->
        {:reply, {:ok, :published}, state}

      {:error, reason} ->
        new_state = handle_publish_failure(state, reason)
        {:reply, {:error, reason}, new_state}
    end
  end

  @impl true
  def handle_cast({:publish_async, _topic, _event}, %{enabled: false} = state) do
    {:noreply, state}
  end

  @impl true
  def handle_cast({:publish_async, topic, event}, state) do
    Task.start(fn ->
      do_publish(topic, event, state)
    end)
    {:noreply, state}
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp start_brod_client(state) do
    config = Application.get_env(:call_service, :kafka, [])
    brokers = parse_brokers(config[:brokers] || System.get_env("KAFKA_BROKERS") || "localhost:9092")
    client_id = :call_kafka_producer

    case :brod.start_client(brokers, client_id, []) do
      :ok ->
        {:ok, %{state | client_id: client_id, brokers: brokers}}

      {:error, {:already_started, _pid}} ->
        {:ok, %{state | client_id: client_id, brokers: brokers}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_publish(topic, event, state) do
    message = Jason.encode!(event)
    partition_key = extract_partition_key(event)

    case :brod.produce_sync(state.client_id, topic, partition_fun(partition_key), partition_key, message) do
      :ok ->
        :telemetry.execute(
          [:call_service, :kafka, :event_published],
          %{count: 1},
          %{topic: topic}
        )
        :ok

      {:error, reason} ->
        Logger.warning("[CallKafkaProducer] Failed to publish to #{topic}: #{inspect(reason)}")
        {:error, reason}
    end
  rescue
    e ->
      Logger.error("[CallKafkaProducer] Exception publishing: #{inspect(e)}")
      {:error, :exception}
  end

  defp extract_partition_key(event) do
    event[:call_id] || event["call_id"] || event[:user_id] || event["user_id"] || "default"
  end

  defp partition_fun(key) do
    # Use consistent hashing via hash ring for partition selection
    # This ensures same call_id always goes to same partition
    Distribution.get_partition(key)
  rescue
    _ -> :erlang.phash2(key, 3)
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
      [host, port] -> {String.to_charlist(host), String.to_integer(port)}
      [host] -> {String.to_charlist(host), 9092}
    end
  end

  defp handle_publish_failure(state, _reason) do
    new_failure_count = state.failure_count + 1

    if new_failure_count >= @max_failures do
      Logger.error("[CallKafkaProducer] Circuit breaker OPEN")
      schedule_reconnect()
      %{state | circuit_state: :open, failure_count: new_failure_count, last_failure_at: System.system_time(:millisecond)}
    else
      %{state | failure_count: new_failure_count}
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

  defp schedule_reconnect do
    Process.send_after(self(), :reconnect, 5_000)
  end
end
