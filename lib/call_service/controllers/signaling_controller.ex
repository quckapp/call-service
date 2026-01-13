defmodule CallService.SignalingController do
  use Phoenix.Controller, formats: [:json]

  alias CallService.SignalingServer

  def offer(conn, %{"call_id" => call_id} = params) do
    from_user_id = conn.assigns[:user_id]
    to_user_id = params["to_user_id"]
    sdp = params["sdp"]

    SignalingServer.send_offer(call_id, from_user_id, to_user_id, sdp)
    json(conn, %{success: true})
  end

  def answer(conn, %{"call_id" => call_id} = params) do
    from_user_id = conn.assigns[:user_id]
    to_user_id = params["to_user_id"]
    sdp = params["sdp"]

    SignalingServer.send_answer(call_id, from_user_id, to_user_id, sdp)
    json(conn, %{success: true})
  end

  def ice_candidate(conn, %{"call_id" => call_id} = params) do
    from_user_id = conn.assigns[:user_id]
    to_user_id = params["to_user_id"]
    candidate = params["candidate"]

    SignalingServer.send_ice_candidate(call_id, from_user_id, to_user_id, candidate)
    json(conn, %{success: true})
  end
end
