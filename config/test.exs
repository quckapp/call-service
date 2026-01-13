import Config

config :call_service, CallService.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4003],
  secret_key_base: "test_secret_key_base",
  server: false

config :logger, level: :warning
