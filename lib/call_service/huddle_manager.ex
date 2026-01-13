defmodule CallService.HuddleManager do
  use GenServer
  require Logger

  alias CallService.{Repo, RedisClient}
  alias Phoenix.PubSub

  @max_huddle_participants 50

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    {:ok, %{}}
  end

  # Public API
  def create_huddle(params) do
    GenServer.call(__MODULE__, {:create_huddle, params})
  end

  def get_huddle(huddle_id) do
    Repo.get_huddle(huddle_id)
  end

  def get_channel_huddle(channel_id) do
    case RedisClient.get_channel_huddle(channel_id) do
      nil -> nil
      huddle_id -> get_huddle(huddle_id)
    end
  end

  def join_huddle(huddle_id, user_id) do
    GenServer.call(__MODULE__, {:join_huddle, huddle_id, user_id})
  end

  def leave_huddle(huddle_id, user_id) do
    GenServer.call(__MODULE__, {:leave_huddle, huddle_id, user_id})
  end

  def end_huddle(huddle_id, user_id) do
    GenServer.call(__MODULE__, {:end_huddle, huddle_id, user_id})
  end

  def start_channel_huddle(channel_id, user_id, workspace_id) do
    # Check if huddle already exists
    case get_channel_huddle(channel_id) do
      nil ->
        create_huddle(%{
          "channel_id" => channel_id,
          "workspace_id" => workspace_id,
          "initiator_id" => user_id
        })
      huddle ->
        {:ok, huddle}
    end
  end

  # GenServer callbacks
  @impl true
  def handle_call({:create_huddle, params}, _from, state) do
    huddle_id = UUID.uuid4()

    huddle_data = %{
      "_id" => huddle_id,
      "channel_id" => params["channel_id"],
      "workspace_id" => params["workspace_id"],
      "initiator_id" => params["initiator_id"],
      "status" => "active",
      "participants" => [],
      "created_at" => DateTime.utc_now(),
      "updated_at" => DateTime.utc_now()
    }

    case Repo.create_huddle(huddle_data) do
      {:ok, _} ->
        RedisClient.set_channel_huddle(params["channel_id"], huddle_id)
        broadcast_huddle_event(params["channel_id"], :huddle_started, huddle_data)
        {:reply, {:ok, huddle_data}, state}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:join_huddle, huddle_id, user_id}, _from, state) do
    case get_huddle(huddle_id) do
      nil ->
        {:reply, {:error, "Huddle not found"}, state}
      huddle ->
        if length(huddle["participants"]) >= @max_huddle_participants do
          {:reply, {:error, "Huddle is full"}, state}
        else
          participant = %{
            "user_id" => user_id,
            "joined_at" => DateTime.utc_now(),
            "audio_enabled" => true,
            "video_enabled" => false
          }

          Repo.add_huddle_participant(huddle_id, participant)

          broadcast_huddle_event(huddle["channel_id"], :participant_joined, %{
            huddle_id: huddle_id,
            user_id: user_id
          })

          {:reply, {:ok, huddle}, state}
        end
    end
  end

  @impl true
  def handle_call({:leave_huddle, huddle_id, user_id}, _from, state) do
    case get_huddle(huddle_id) do
      nil ->
        {:reply, {:error, "Huddle not found"}, state}
      huddle ->
        Repo.remove_huddle_participant(huddle_id, user_id)

        # Check if huddle is now empty
        updated_huddle = get_huddle(huddle_id)
        if Enum.empty?(updated_huddle["participants"]) do
          end_huddle_internal(huddle_id, huddle)
        else
          broadcast_huddle_event(huddle["channel_id"], :participant_left, %{
            huddle_id: huddle_id,
            user_id: user_id
          })
        end

        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call({:end_huddle, huddle_id, user_id}, _from, state) do
    case get_huddle(huddle_id) do
      nil ->
        {:reply, {:error, "Huddle not found"}, state}
      huddle ->
        if huddle["initiator_id"] == user_id do
          end_huddle_internal(huddle_id, huddle)
          {:reply, :ok, state}
        else
          {:reply, {:error, "Only initiator can end the huddle"}, state}
        end
    end
  end

  defp end_huddle_internal(huddle_id, huddle) do
    duration = DateTime.diff(DateTime.utc_now(), huddle["created_at"], :second)

    Repo.update_huddle(huddle_id, %{
      "status" => "ended",
      "ended_at" => DateTime.utc_now(),
      "duration" => duration
    })

    RedisClient.clear_channel_huddle(huddle["channel_id"])

    broadcast_huddle_event(huddle["channel_id"], :huddle_ended, %{
      huddle_id: huddle_id,
      duration: duration
    })
  end

  defp broadcast_huddle_event(channel_id, event, data) do
    PubSub.broadcast(
      CallService.PubSub,
      "huddle:#{channel_id}",
      {event, data}
    )
  end
end
