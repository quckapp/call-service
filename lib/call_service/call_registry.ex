defmodule CallService.CallRegistry do
  use GenServer
  require Logger

  alias CallService.{Repo, RedisClient}
  alias Phoenix.PubSub

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    {:ok, %{}}
  end

  # Public API
  def create_call(params) do
    GenServer.call(__MODULE__, {:create_call, params})
  end

  def get_call(call_id) do
    case RedisClient.get_active_call(call_id) do
      nil -> Repo.get_call(call_id)
      call -> call
    end
  end

  def join_call(call_id, user_id, opts \\ %{}) do
    GenServer.call(__MODULE__, {:join_call, call_id, user_id, opts})
  end

  def leave_call(call_id, user_id) do
    GenServer.call(__MODULE__, {:leave_call, call_id, user_id})
  end

  def end_call(call_id, user_id) do
    GenServer.call(__MODULE__, {:end_call, call_id, user_id})
  end

  def update_participant_state(call_id, user_id, updates) do
    GenServer.cast(__MODULE__, {:update_participant, call_id, user_id, updates})
  end

  def get_participants(call_id) do
    RedisClient.get_participants(call_id)
  end

  # GenServer callbacks
  @impl true
  def handle_call({:create_call, params}, _from, state) do
    call_id = UUID.uuid4()

    call_data = %{
      "_id" => call_id,
      "type" => params["type"] || "audio",
      "channel_id" => params["channel_id"],
      "workspace_id" => params["workspace_id"],
      "initiator_id" => params["initiator_id"],
      "status" => "active",
      "participants" => [],
      "created_at" => DateTime.utc_now(),
      "updated_at" => DateTime.utc_now()
    }

    case Repo.create_call(call_data) do
      {:ok, _} ->
        RedisClient.set_active_call(call_id, call_data)
        broadcast_call_event(call_data["channel_id"], :call_started, call_data)
        {:reply, {:ok, call_data}, state}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:join_call, call_id, user_id, opts}, _from, state) do
    case get_call(call_id) do
      nil ->
        {:reply, {:error, "Call not found"}, state}
      call ->
        # Check if user is already in another call
        case RedisClient.get_user_call(user_id) do
          nil -> :ok
          existing_call_id when existing_call_id != call_id ->
            leave_call(existing_call_id, user_id)
          _ -> :ok
        end

        participant = %{
          "user_id" => user_id,
          "joined_at" => DateTime.utc_now(),
          "audio_enabled" => Map.get(opts, "audio_enabled", true),
          "video_enabled" => Map.get(opts, "video_enabled", false),
          "screen_sharing" => false
        }

        Repo.add_participant(call_id, participant)
        RedisClient.add_participant(call_id, user_id)
        RedisClient.set_user_call(user_id, call_id)

        # Update cache
        updated_call = Map.update!(call, "participants", &[participant | &1])
        RedisClient.set_active_call(call_id, updated_call)

        broadcast_call_event(call["channel_id"], :participant_joined, %{
          call_id: call_id,
          user_id: user_id,
          participant: participant
        })

        {:reply, {:ok, updated_call}, state}
    end
  end

  @impl true
  def handle_call({:leave_call, call_id, user_id}, _from, state) do
    case get_call(call_id) do
      nil ->
        {:reply, {:error, "Call not found"}, state}
      call ->
        Repo.remove_participant(call_id, user_id)
        RedisClient.remove_participant(call_id, user_id)
        RedisClient.clear_user_call(user_id)

        participant_count = RedisClient.get_participant_count(call_id)

        if participant_count == 0 do
          end_call_internal(call_id, call)
        else
          updated_call = Map.update!(call, "participants", fn ps ->
            Enum.reject(ps, &(&1["user_id"] == user_id))
          end)
          RedisClient.set_active_call(call_id, updated_call)
        end

        broadcast_call_event(call["channel_id"], :participant_left, %{
          call_id: call_id,
          user_id: user_id
        })

        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call({:end_call, call_id, user_id}, _from, state) do
    case get_call(call_id) do
      nil ->
        {:reply, {:error, "Call not found"}, state}
      call ->
        if call["initiator_id"] == user_id do
          end_call_internal(call_id, call)
          {:reply, :ok, state}
        else
          {:reply, {:error, "Only initiator can end the call"}, state}
        end
    end
  end

  @impl true
  def handle_cast({:update_participant, call_id, user_id, updates}, state) do
    Repo.update_participant(call_id, user_id, updates)

    case get_call(call_id) do
      nil -> :ok
      call ->
        broadcast_call_event(call["channel_id"], :participant_updated, %{
          call_id: call_id,
          user_id: user_id,
          updates: updates
        })
    end

    {:noreply, state}
  end

  defp end_call_internal(call_id, call) do
    duration = DateTime.diff(DateTime.utc_now(), call["created_at"], :second)

    Repo.update_call(call_id, %{
      "status" => "ended",
      "ended_at" => DateTime.utc_now(),
      "duration" => duration
    })

    # Save to call log
    Repo.save_call_log(%{
      "call_id" => call_id,
      "type" => call["type"],
      "channel_id" => call["channel_id"],
      "workspace_id" => call["workspace_id"],
      "initiator_id" => call["initiator_id"],
      "participants" => call["participants"],
      "duration" => duration,
      "created_at" => call["created_at"],
      "ended_at" => DateTime.utc_now()
    })

    # Clear all participants
    for user_id <- RedisClient.get_participants(call_id) do
      RedisClient.clear_user_call(user_id)
    end

    RedisClient.delete_active_call(call_id)

    broadcast_call_event(call["channel_id"], :call_ended, %{
      call_id: call_id,
      duration: duration
    })
  end

  defp broadcast_call_event(channel_id, event, data) do
    PubSub.broadcast(
      CallService.PubSub,
      "call:#{channel_id}",
      {event, data}
    )
  end
end
