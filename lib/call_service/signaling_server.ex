defmodule CallService.SignalingServer do
  use GenServer
  require Logger

  alias CallService.RedisClient
  alias Phoenix.PubSub

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    {:ok, %{}}
  end

  # Public API
  def send_offer(call_id, from_user_id, to_user_id, sdp) do
    signal = %{
      type: "offer",
      from: from_user_id,
      sdp: sdp,
      timestamp: System.system_time(:millisecond)
    }

    RedisClient.push_signal(call_id, to_user_id, signal)
    broadcast_signal(call_id, to_user_id, signal)
  end

  def send_answer(call_id, from_user_id, to_user_id, sdp) do
    signal = %{
      type: "answer",
      from: from_user_id,
      sdp: sdp,
      timestamp: System.system_time(:millisecond)
    }

    RedisClient.push_signal(call_id, to_user_id, signal)
    broadcast_signal(call_id, to_user_id, signal)
  end

  def send_ice_candidate(call_id, from_user_id, to_user_id, candidate) do
    signal = %{
      type: "ice-candidate",
      from: from_user_id,
      candidate: candidate,
      timestamp: System.system_time(:millisecond)
    }

    RedisClient.push_signal(call_id, to_user_id, signal)
    broadcast_signal(call_id, to_user_id, signal)
  end

  def get_pending_signals(call_id, user_id) do
    RedisClient.pop_signals(call_id, user_id)
  end

  def get_ice_servers do
    webrtc_config = Application.get_env(:call_service, :webrtc)

    stun_servers = webrtc_config[:stun_servers] || []
    turn_server = webrtc_config[:turn_server]
    turn_username = webrtc_config[:turn_username]
    turn_credential = webrtc_config[:turn_credential]

    servers = Enum.map(stun_servers, fn url ->
      %{urls: url}
    end)

    if turn_server && turn_username && turn_credential do
      turn = %{
        urls: turn_server,
        username: turn_username,
        credential: turn_credential
      }
      servers ++ [turn]
    else
      servers
    end
  end

  def generate_turn_credentials(user_id) do
    webrtc_config = Application.get_env(:call_service, :webrtc)

    # Generate time-limited credentials
    ttl = 86400  # 24 hours
    timestamp = System.system_time(:second) + ttl
    username = "#{timestamp}:#{user_id}"

    # In production, use HMAC-SHA1 to generate credential
    # For now, return config credential
    %{
      username: username,
      credential: webrtc_config[:turn_credential] || "",
      ttl: ttl,
      urls: [webrtc_config[:turn_server]]
    }
  end

  defp broadcast_signal(call_id, to_user_id, signal) do
    PubSub.broadcast(
      CallService.PubSub,
      "signal:#{call_id}:#{to_user_id}",
      {:signal, signal}
    )
  end
end
