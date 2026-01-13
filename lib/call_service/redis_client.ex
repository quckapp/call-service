defmodule CallService.RedisClient do
  use GenServer

  @pool_size 5
  @prefix "call:"

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    redis_url = Application.get_env(:call_service, :redis)[:url]

    children =
      for i <- 0..(@pool_size - 1) do
        Supervisor.child_spec(
          {Redix, {redis_url, [name: :"redix_#{i}"]}},
          id: {Redix, i}
        )
      end

    Supervisor.start_link(children, strategy: :one_for_one)
    {:ok, %{}}
  end

  defp command(args) do
    Redix.command(:"redix_#{:rand.uniform(@pool_size) - 1}", args)
  end

  # Active calls cache
  def set_active_call(call_id, call_data, ttl \\ 3600) do
    key = "#{@prefix}active:#{call_id}"
    data = Jason.encode!(call_data)
    command(["SETEX", key, ttl, data])
  end

  def get_active_call(call_id) do
    key = "#{@prefix}active:#{call_id}"
    case command(["GET", key]) do
      {:ok, nil} -> nil
      {:ok, data} -> Jason.decode!(data)
      _ -> nil
    end
  end

  def delete_active_call(call_id) do
    key = "#{@prefix}active:#{call_id}"
    command(["DEL", key])
  end

  # Call participants tracking
  def add_participant(call_id, user_id) do
    key = "#{@prefix}participants:#{call_id}"
    command(["SADD", key, user_id])
  end

  def remove_participant(call_id, user_id) do
    key = "#{@prefix}participants:#{call_id}"
    command(["SREM", key, user_id])
  end

  def get_participants(call_id) do
    key = "#{@prefix}participants:#{call_id}"
    case command(["SMEMBERS", key]) do
      {:ok, members} -> members
      _ -> []
    end
  end

  def get_participant_count(call_id) do
    key = "#{@prefix}participants:#{call_id}"
    case command(["SCARD", key]) do
      {:ok, count} -> count
      _ -> 0
    end
  end

  # User current call tracking
  def set_user_call(user_id, call_id) do
    key = "#{@prefix}user:#{user_id}"
    command(["SET", key, call_id])
  end

  def get_user_call(user_id) do
    key = "#{@prefix}user:#{user_id}"
    case command(["GET", key]) do
      {:ok, call_id} -> call_id
      _ -> nil
    end
  end

  def clear_user_call(user_id) do
    key = "#{@prefix}user:#{user_id}"
    command(["DEL", key])
  end

  # Huddle tracking
  def set_channel_huddle(channel_id, huddle_id) do
    key = "#{@prefix}channel_huddle:#{channel_id}"
    command(["SET", key, huddle_id])
  end

  def get_channel_huddle(channel_id) do
    key = "#{@prefix}channel_huddle:#{channel_id}"
    case command(["GET", key]) do
      {:ok, huddle_id} -> huddle_id
      _ -> nil
    end
  end

  def clear_channel_huddle(channel_id) do
    key = "#{@prefix}channel_huddle:#{channel_id}"
    command(["DEL", key])
  end

  # Signaling message queue
  def push_signal(call_id, user_id, signal) do
    key = "#{@prefix}signals:#{call_id}:#{user_id}"
    data = Jason.encode!(signal)
    command(["RPUSH", key, data])
    command(["EXPIRE", key, 300])  # 5 minute expiry
  end

  def pop_signals(call_id, user_id) do
    key = "#{@prefix}signals:#{call_id}:#{user_id}"
    case command(["LRANGE", key, 0, -1]) do
      {:ok, signals} ->
        command(["DEL", key])
        Enum.map(signals, &Jason.decode!/1)
      _ -> []
    end
  end
end
