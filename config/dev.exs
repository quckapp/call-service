import Config

config :call_service, CallService.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: 4002],
  check_origin: false, debug_errors: true,
  secret_key_base: "dev_secret_key_base_call_service_quckchat",
  watchers: []

config :logger, :console, format: "[$level] $message\n"
config :phoenix, :plug_init_mode, :runtime
