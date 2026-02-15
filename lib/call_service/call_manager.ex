defmodule CallService.CallManager do
  @moduledoc """
  Call Manager - Manages call lifecycle and state.

  ## Design Patterns Used:
  - **State Machine**: Call states (ringing, connected, ended)
  - **Actor Model**: One process per active call
  - **Observer Pattern**: Notifies participants of state changes

  ## Responsibilities:
  - Create and manage call sessions
  - Handle call state transitions
  - Coordinate between participants
  - Track call history and metrics
  """
  use GenServer
  require Logger

  alias CallService.Kafka.Producer

  # Valid call states
  @valid_states ~w(initiating ringing connecting connected on_hold ended failed)a

  # Valid call types
  @valid_types ~w(audio video)a

  # Call timeout (60 seconds for ringing)
  @ring_timeout_ms 60_000
  @connect_timeout_ms 30_000

  defstruct [
    :calls,
    :call_count,
    :stats
  ]

  # ============================================================================
  # Public API
  # ============================================================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Initiate a new call"
  def initiate_call(caller_id, callee_id, call_type, opts \\ []) do
    GenServer.call(__MODULE__, {:initiate_call, caller_id, callee_id, call_type, opts})
  end

  @doc "Accept an incoming call"
  def accept_call(call_id, user_id) do
    GenServer.call(__MODULE__, {:accept_call, call_id, user_id})
  end

  @doc "Reject an incoming call"
  def reject_call(call_id, user_id, reason \\ "rejected") do
    GenServer.call(__MODULE__, {:reject_call, call_id, user_id, reason})
  end

  @doc "End an active call"
  def end_call(call_id, user_id) do
    GenServer.call(__MODULE__, {:end_call, call_id, user_id})
  end

  @doc "Get call information"
  def get_call(call_id) do
    GenServer.call(__MODULE__, {:get_call, call_id})
  end

  @doc "Get active calls for a user"
  def get_user_calls(user_id) do
    GenServer.call(__MODULE__, {:get_user_calls, user_id})
  end

  @doc "Update call state (for WebRTC events)"
  def update_call_state(call_id, state, metadata \\ %{}) do
    GenServer.call(__MODULE__, {:update_state, call_id, state, metadata})
  end

  @doc "Get call statistics"
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  @doc "Get call participants"
  def get_participants(call_id) do
    GenServer.call(__MODULE__, {:get_participants, call_id})
  end

  @doc "Invite a user to an existing call"
  def invite_to_call(call_id, inviter_id, invitee_id) do
    GenServer.call(__MODULE__, {:invite_to_call, call_id, inviter_id, invitee_id})
  end

  @doc "Answer a call (alias for accept_call with SDP answer)"
  def answer_call(call_id, user_id, sdp_answer) do
    GenServer.call(__MODULE__, {:answer_call, call_id, user_id, sdp_answer})
  end

  @doc "Toggle mute status for a participant"
  def toggle_mute(call_id, user_id, muted) do
    GenServer.call(__MODULE__, {:toggle_mute, call_id, user_id, muted})
  end

  @doc "Get all active calls (optionally for a specific user)"
  def get_active_calls(user_id \\ nil) do
    GenServer.call(__MODULE__, {:get_active_calls, user_id})
  end

  @doc "Answer a call (alias without SDP answer)"
  def answer_call(call_id, user_id) do
    answer_call(call_id, user_id, nil)
  end

  @doc "Get call history for a user"
  def get_call_history(user_id, opts \\ []) do
    GenServer.call(__MODULE__, {:get_call_history, user_id, opts})
  end

  @doc "Update user availability status"
  def update_user_availability(user_id, status) do
    GenServer.call(__MODULE__, {:update_user_availability, user_id, status})
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl true
  def init(_opts) do
    # Initialize ETS table for fast lookups
    :ets.new(:call_manager_calls, [:set, :named_table, :public])
    :ets.new(:call_manager_user_calls, [:bag, :named_table, :public])
    :ets.new(:call_manager_stats, [:set, :named_table, :public])

    init_stats()

    state = %__MODULE__{
      calls: %{},
      call_count: 0,
      stats: %{}
    }

    Logger.info("[CallManager] Started")
    {:ok, state}
  end

  @impl true
  def handle_call({:initiate_call, caller_id, callee_id, call_type, opts}, _from, state) do
    with {:ok, call_type_atom} <- validate_call_type(call_type),
         :ok <- check_user_availability(caller_id),
         :ok <- check_user_availability(callee_id) do
      call_id = generate_call_id()

      call = %{
        id: call_id,
        caller_id: caller_id,
        callee_id: callee_id,
        call_type: call_type_atom,
        state: :ringing,
        started_at: DateTime.utc_now(),
        connected_at: nil,
        ended_at: nil,
        metadata: opts[:metadata] || %{},
        conversation_id: opts[:conversation_id]
      }

      # Store in ETS
      :ets.insert(:call_manager_calls, {call_id, call})
      :ets.insert(:call_manager_user_calls, {caller_id, call_id})
      :ets.insert(:call_manager_user_calls, {callee_id, call_id})

      # Schedule ring timeout
      Process.send_after(self(), {:ring_timeout, call_id}, @ring_timeout_ms)

      # Publish event
      publish_call_event("call.initiated", call)

      increment_stat(:calls_initiated)

      {:reply, {:ok, call}, %{state | call_count: state.call_count + 1}}
    else
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:accept_call, call_id, user_id}, _from, state) do
    case get_call_from_ets(call_id) do
      {:ok, call} ->
        if call.callee_id == user_id and call.state == :ringing do
          updated_call = %{call |
            state: :connecting,
            connected_at: DateTime.utc_now()
          }

          :ets.insert(:call_manager_calls, {call_id, updated_call})

          # Schedule connect timeout
          Process.send_after(self(), {:connect_timeout, call_id}, @connect_timeout_ms)

          publish_call_event("call.accepted", updated_call)
          increment_stat(:calls_accepted)

          {:reply, {:ok, updated_call}, state}
        else
          {:reply, {:error, :invalid_action}, state}
        end

      {:error, :not_found} ->
        {:reply, {:error, :call_not_found}, state}
    end
  end

  @impl true
  def handle_call({:reject_call, call_id, user_id, reason}, _from, state) do
    case get_call_from_ets(call_id) do
      {:ok, call} ->
        if call.callee_id == user_id and call.state == :ringing do
          updated_call = %{call |
            state: :ended,
            ended_at: DateTime.utc_now(),
            metadata: Map.put(call.metadata, :end_reason, reason)
          }

          :ets.insert(:call_manager_calls, {call_id, updated_call})
          cleanup_user_call_refs(call)

          publish_call_event("call.rejected", updated_call)
          increment_stat(:calls_rejected)

          {:reply, {:ok, updated_call}, state}
        else
          {:reply, {:error, :invalid_action}, state}
        end

      {:error, :not_found} ->
        {:reply, {:error, :call_not_found}, state}
    end
  end

  @impl true
  def handle_call({:end_call, call_id, user_id}, _from, state) do
    case get_call_from_ets(call_id) do
      {:ok, call} ->
        if user_id in [call.caller_id, call.callee_id] and call.state not in [:ended, :failed] do
          updated_call = %{call |
            state: :ended,
            ended_at: DateTime.utc_now(),
            metadata: Map.put(call.metadata, :ended_by, user_id)
          }

          :ets.insert(:call_manager_calls, {call_id, updated_call})
          cleanup_user_call_refs(call)

          # Calculate duration if was connected
          duration = calculate_duration(call)

          publish_call_event("call.ended", Map.put(updated_call, :duration, duration))
          increment_stat(:calls_ended)

          {:reply, {:ok, updated_call}, state}
        else
          {:reply, {:error, :invalid_action}, state}
        end

      {:error, :not_found} ->
        {:reply, {:error, :call_not_found}, state}
    end
  end

  @impl true
  def handle_call({:get_call, call_id}, _from, state) do
    result = get_call_from_ets(call_id)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:get_user_calls, user_id}, _from, state) do
    call_ids = :ets.lookup(:call_manager_user_calls, user_id)
               |> Enum.map(fn {_, call_id} -> call_id end)

    calls = Enum.flat_map(call_ids, fn call_id ->
      case get_call_from_ets(call_id) do
        {:ok, call} when call.state not in [:ended, :failed] -> [call]
        _ -> []
      end
    end)

    {:reply, {:ok, calls}, state}
  end

  @impl true
  def handle_call({:update_state, call_id, new_state, metadata}, _from, state) do
    case get_call_from_ets(call_id) do
      {:ok, call} ->
        with {:ok, state_atom} <- validate_state(new_state) do
          updated_call = %{call |
            state: state_atom,
            metadata: Map.merge(call.metadata, metadata)
          }

          # Set connected_at if transitioning to connected
          updated_call = if state_atom == :connected and is_nil(call.connected_at) do
            %{updated_call | connected_at: DateTime.utc_now()}
          else
            updated_call
          end

          :ets.insert(:call_manager_calls, {call_id, updated_call})
          publish_call_event("call.state_changed", updated_call)

          {:reply, {:ok, updated_call}, state}
        else
          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      {:error, :not_found} ->
        {:reply, {:error, :call_not_found}, state}
    end
  end

  @impl true
  def handle_call(:stats, _from, state) do
    stats = %{
      total_initiated: get_stat(:calls_initiated),
      total_accepted: get_stat(:calls_accepted),
      total_rejected: get_stat(:calls_rejected),
      total_ended: get_stat(:calls_ended),
      total_failed: get_stat(:calls_failed),
      active_calls: :ets.info(:call_manager_calls, :size)
    }
    {:reply, stats, state}
  end

  @impl true
  def handle_call({:get_participants, call_id}, _from, state) do
    case get_call_from_ets(call_id) do
      {:ok, call} ->
        participants = [
          %{user_id: call.caller_id, role: :caller},
          %{user_id: call.callee_id, role: :callee}
        ]
        {:reply, {:ok, participants}, state}

      {:error, :not_found} ->
        {:reply, {:error, :call_not_found}, state}
    end
  end

  @impl true
  def handle_call({:invite_to_call, call_id, inviter_id, invitee_id}, _from, state) do
    case get_call_from_ets(call_id) do
      {:ok, call} ->
        if inviter_id in [call.caller_id, call.callee_id] and call.state == :connected do
          # For now, just publish an event - real implementation would add to call
          publish_call_event("call.invite_sent", %{
            id: call_id,
            caller_id: inviter_id,
            callee_id: invitee_id,
            call_type: call.call_type,
            state: :ringing
          })
          {:reply, {:ok, %{invited: invitee_id}}, state}
        else
          {:reply, {:error, :invalid_action}, state}
        end

      {:error, :not_found} ->
        {:reply, {:error, :call_not_found}, state}
    end
  end

  @impl true
  def handle_call({:answer_call, call_id, user_id, sdp_answer}, _from, state) do
    case get_call_from_ets(call_id) do
      {:ok, call} ->
        if call.callee_id == user_id and call.state in [:ringing, :connecting] do
          updated_call = %{call |
            state: :connected,
            connected_at: DateTime.utc_now(),
            metadata: Map.put(call.metadata, :sdp_answer, sdp_answer)
          }

          :ets.insert(:call_manager_calls, {call_id, updated_call})

          publish_call_event("call.answered", updated_call)
          increment_stat(:calls_accepted)

          {:reply, {:ok, updated_call}, state}
        else
          {:reply, {:error, :invalid_action}, state}
        end

      {:error, :not_found} ->
        {:reply, {:error, :call_not_found}, state}
    end
  end

  @impl true
  def handle_call({:toggle_mute, call_id, user_id, muted}, _from, state) do
    case get_call_from_ets(call_id) do
      {:ok, call} ->
        if user_id in [call.caller_id, call.callee_id] and call.state == :connected do
          mute_states = Map.get(call.metadata, :mute_states, %{})
          updated_mute_states = Map.put(mute_states, user_id, muted)

          updated_call = %{call |
            metadata: Map.put(call.metadata, :mute_states, updated_mute_states)
          }

          :ets.insert(:call_manager_calls, {call_id, updated_call})

          publish_call_event("call.mute_toggled", Map.put(updated_call, :muted_user, %{user_id: user_id, muted: muted}))

          {:reply, {:ok, %{user_id: user_id, muted: muted}}, state}
        else
          {:reply, {:error, :invalid_action}, state}
        end

      {:error, :not_found} ->
        {:reply, {:error, :call_not_found}, state}
    end
  end

  @impl true
  def handle_call({:get_active_calls, nil}, _from, state) do
    calls = :ets.tab2list(:call_manager_calls)
            |> Enum.map(fn {_, call} -> call end)
            |> Enum.filter(fn call -> call.state not in [:ended, :failed] end)
    {:reply, {:ok, calls}, state}
  end

  @impl true
  def handle_call({:get_active_calls, user_id}, _from, state) do
    call_ids = :ets.lookup(:call_manager_user_calls, user_id)
               |> Enum.map(fn {_, call_id} -> call_id end)

    calls = Enum.flat_map(call_ids, fn call_id ->
      case get_call_from_ets(call_id) do
        {:ok, call} when call.state not in [:ended, :failed] -> [call]
        _ -> []
      end
    end)

    {:reply, {:ok, calls}, state}
  end

  @impl true
  def handle_call({:get_call_history, user_id, opts}, _from, state) do
    limit = Keyword.get(opts, :limit, 50)
    call_ids = :ets.lookup(:call_manager_user_calls, user_id)
               |> Enum.map(fn {_, call_id} -> call_id end)

    calls = call_ids
            |> Enum.flat_map(fn call_id ->
              case get_call_from_ets(call_id) do
                {:ok, call} -> [call]
                _ -> []
              end
            end)
            |> Enum.sort_by(& &1.started_at, {:desc, DateTime})
            |> Enum.take(limit)

    {:reply, {:ok, calls}, state}
  end

  @impl true
  def handle_call({:update_user_availability, user_id, status}, _from, state) do
    # Store user availability in ETS for quick lookups
    :ets.insert(:call_manager_stats, {{:user_availability, user_id}, status})
    {:reply, {:ok, %{user_id: user_id, status: status}}, state}
  end

  @impl true
  def handle_info({:ring_timeout, call_id}, state) do
    case get_call_from_ets(call_id) do
      {:ok, call} when call.state == :ringing ->
        updated_call = %{call |
          state: :failed,
          ended_at: DateTime.utc_now(),
          metadata: Map.put(call.metadata, :end_reason, "ring_timeout")
        }

        :ets.insert(:call_manager_calls, {call_id, updated_call})
        cleanup_user_call_refs(call)

        publish_call_event("call.timeout", updated_call)
        increment_stat(:calls_failed)

        Logger.info("[CallManager] Call #{call_id} timed out (no answer)")

      _ ->
        :ok
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:connect_timeout, call_id}, state) do
    case get_call_from_ets(call_id) do
      {:ok, call} when call.state == :connecting ->
        updated_call = %{call |
          state: :failed,
          ended_at: DateTime.utc_now(),
          metadata: Map.put(call.metadata, :end_reason, "connect_timeout")
        }

        :ets.insert(:call_manager_calls, {call_id, updated_call})
        cleanup_user_call_refs(call)

        publish_call_event("call.failed", updated_call)
        increment_stat(:calls_failed)

        Logger.info("[CallManager] Call #{call_id} failed to connect")

      _ ->
        :ok
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp generate_call_id do
    "call_" <> (:crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower))
  end

  defp validate_call_type(type) when type in ["audio", "video"] do
    {:ok, String.to_atom(type)}
  end
  defp validate_call_type(type) when type in [:audio, :video] do
    {:ok, type}
  end
  defp validate_call_type(_), do: {:error, :invalid_call_type}

  defp validate_state(state) when is_binary(state) do
    atom = String.to_existing_atom(state)
    if atom in @valid_states, do: {:ok, atom}, else: {:error, :invalid_state}
  rescue
    ArgumentError -> {:error, :invalid_state}
  end
  defp validate_state(state) when state in @valid_states, do: {:ok, state}
  defp validate_state(_), do: {:error, :invalid_state}

  defp check_user_availability(_user_id) do
    # In production, check if user is online and not in another call
    :ok
  end

  defp get_call_from_ets(call_id) do
    case :ets.lookup(:call_manager_calls, call_id) do
      [{^call_id, call}] -> {:ok, call}
      [] -> {:error, :not_found}
    end
  end

  defp cleanup_user_call_refs(call) do
    :ets.delete_object(:call_manager_user_calls, {call.caller_id, call.id})
    :ets.delete_object(:call_manager_user_calls, {call.callee_id, call.id})
  end

  defp calculate_duration(call) do
    case call.connected_at do
      nil -> 0
      connected_at ->
        ended_at = call.ended_at || DateTime.utc_now()
        DateTime.diff(ended_at, connected_at, :second)
    end
  end

  defp publish_call_event(event_type, call) do
    event = %{
      event_type: event_type,
      call_id: call.id,
      caller_id: call.caller_id,
      callee_id: call.callee_id,
      call_type: call.call_type,
      state: call.state,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    Producer.publish_call_event(event)
  rescue
    _ -> :ok
  end

  defp init_stats do
    :ets.insert(:call_manager_stats, {:calls_initiated, 0})
    :ets.insert(:call_manager_stats, {:calls_accepted, 0})
    :ets.insert(:call_manager_stats, {:calls_rejected, 0})
    :ets.insert(:call_manager_stats, {:calls_ended, 0})
    :ets.insert(:call_manager_stats, {:calls_failed, 0})
  end

  defp get_stat(key) do
    case :ets.lookup(:call_manager_stats, key) do
      [{^key, value}] -> value
      [] -> 0
    end
  end

  defp increment_stat(key) do
    :ets.update_counter(:call_manager_stats, key, 1)
  rescue
    _ -> :ok
  end
end
