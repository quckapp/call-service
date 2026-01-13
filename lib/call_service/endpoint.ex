defmodule CallService.Endpoint do
  use Phoenix.Endpoint, otp_app: :call_service

  socket "/socket", CallService.UserSocket, websocket: [timeout: 45_000], longpoll: false

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]
  plug Plug.Parsers, parsers: [:urlencoded, :multipart, :json], pass: ["*/*"], json_decoder: Jason
  plug Plug.MethodOverride
  plug Plug.Head
  plug CORSPlug, origin: ["*"]
  plug CallService.Router
end
