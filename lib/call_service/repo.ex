defmodule CallService.Repo do
  use GenServer

  @pool_name :mongo_pool

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    mongodb_config = Application.get_env(:call_service, :mongodb)

    children = [
      %{
        id: :mongo_pool,
        start: {Mongo, :start_link, [[
          name: @pool_name,
          url: mongodb_config[:url],
          pool_size: mongodb_config[:pool_size] || 10
        ]]}
      }
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
    {:ok, %{}}
  end

  def get_pool, do: @pool_name

  # Call operations
  def create_call(call_data) do
    Mongo.insert_one(@pool_name, "calls", call_data)
  end

  def get_call(call_id) do
    Mongo.find_one(@pool_name, "calls", %{"_id" => call_id})
  end

  def update_call(call_id, updates) do
    Mongo.update_one(
      @pool_name,
      "calls",
      %{"_id" => call_id},
      %{"$set" => Map.merge(updates, %{"updated_at" => DateTime.utc_now()})}
    )
  end

  def add_participant(call_id, participant) do
    Mongo.update_one(
      @pool_name,
      "calls",
      %{"_id" => call_id},
      %{"$push" => %{"participants" => participant}}
    )
  end

  def remove_participant(call_id, user_id) do
    Mongo.update_one(
      @pool_name,
      "calls",
      %{"_id" => call_id},
      %{"$pull" => %{"participants" => %{"user_id" => user_id}}}
    )
  end

  def update_participant(call_id, user_id, updates) do
    Mongo.update_one(
      @pool_name,
      "calls",
      %{"_id" => call_id, "participants.user_id" => user_id},
      %{"$set" => Enum.map(updates, fn {k, v} -> {"participants.$.#{k}", v} end) |> Map.new()}
    )
  end

  # Huddle operations
  def create_huddle(huddle_data) do
    Mongo.insert_one(@pool_name, "huddles", huddle_data)
  end

  def get_huddle(huddle_id) do
    Mongo.find_one(@pool_name, "huddles", %{"_id" => huddle_id})
  end

  def get_channel_huddle(channel_id) do
    Mongo.find_one(@pool_name, "huddles", %{
      "channel_id" => channel_id,
      "status" => "active"
    })
  end

  def update_huddle(huddle_id, updates) do
    Mongo.update_one(
      @pool_name,
      "huddles",
      %{"_id" => huddle_id},
      %{"$set" => Map.merge(updates, %{"updated_at" => DateTime.utc_now()})}
    )
  end

  def add_huddle_participant(huddle_id, participant) do
    Mongo.update_one(
      @pool_name,
      "huddles",
      %{"_id" => huddle_id},
      %{"$push" => %{"participants" => participant}}
    )
  end

  def remove_huddle_participant(huddle_id, user_id) do
    Mongo.update_one(
      @pool_name,
      "huddles",
      %{"_id" => huddle_id},
      %{"$pull" => %{"participants" => %{"user_id" => user_id}}}
    )
  end

  # Call history
  def save_call_log(log_data) do
    Mongo.insert_one(@pool_name, "call_logs", log_data)
  end

  def get_user_call_history(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    skip = Keyword.get(opts, :skip, 0)

    Mongo.find(@pool_name, "call_logs", %{
      "$or" => [
        %{"caller_id" => user_id},
        %{"participants.user_id" => user_id}
      ]
    }, [sort: %{"created_at" => -1}, limit: limit, skip: skip])
    |> Enum.to_list()
  end

  # Recording operations
  def create_recording(recording_data) do
    Mongo.insert_one(@pool_name, "recordings", recording_data)
  end

  def get_recording(recording_id) do
    Mongo.find_one(@pool_name, "recordings", %{"_id" => recording_id})
  end

  def get_call_recordings(call_id) do
    Mongo.find(@pool_name, "recordings", %{"call_id" => call_id})
    |> Enum.to_list()
  end

  def update_recording(recording_id, updates) do
    Mongo.update_one(
      @pool_name,
      "recordings",
      %{"_id" => recording_id},
      %{"$set" => updates}
    )
  end
end
