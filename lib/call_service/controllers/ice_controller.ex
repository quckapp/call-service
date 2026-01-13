defmodule CallService.IceController do
  use Phoenix.Controller, formats: [:json]

  alias CallService.SignalingServer

  def get_servers(conn, _params) do
    servers = SignalingServer.get_ice_servers()
    json(conn, %{ice_servers: servers})
  end

  def get_credentials(conn, _params) do
    user_id = conn.assigns[:user_id]
    credentials = SignalingServer.generate_turn_credentials(user_id)
    json(conn, credentials)
  end
end
