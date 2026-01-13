import Config

config :call_service, CallService.Endpoint,
  url: [host: System.get_env("PHX_HOST") || "example.com", port: 443, scheme: "https"],
  http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}, port: String.to_integer(System.get_env("PORT") || "4002")],
  secret_key_base: System.get_env("SECRET_KEY_BASE"),
  server: true

config :logger, level: :info
