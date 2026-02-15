defmodule CallService.RedisClient do
  use GenServer

  alias CallService.{CircuitBreaker, Distribution}

  @pool_size 5
  @prefix "call:"

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    redis_config = Application.get_env(:call_service, :redis, [])

    # Build Redix options from config
    redix_opts = [
      host: redis_config[:host] || "localhost",
      port: redis_config[:port] || 6379,
      database: redis_config[:database] || 4
    ]

    # Add password if configured
    redix_opts = if redis_config[:password] do
      Keyword.put(redix_opts, :password, redis_config[:password])
    else
      redix_opts
    end

    children =
      for i <- 0..(@pool_size - 1) do
        opts = Keyword.put(redix_opts, :name, :"redix_#{i}")
        Supervisor.child_spec(
          {Redix, opts},
          id: {Redix, i}
        )
      end

    Supervisor.start_link(children, strategy: :one_for_one)
    {:ok, %{}}
  end

  defp command(args) do
    CircuitBreaker.call(:redis, fn ->
      pool_idx = get_pool_index(args)
      Redix.command(:"redix_#{pool_idx}", args)
    end, default: {:error, :redis_unavailable})
  end

  # Use consistent hashing for pool selection based on the key
  defp get_pool_index(args) do
    key = extract_key(args)
    if key do
      Distribution.get_redis_pool(key)
    else
      :rand.uniform(@pool_size) - 1
    end
  rescue
    _ -> :rand.uniform(@pool_size) - 1
  end

  # Extract the key from Redis command args for consistent hashing
  defp extract_key([_cmd, key | _rest]) when is_binary(key), do: key
  defp extract_key(_), do: nil

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
