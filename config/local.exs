# =============================================================================
# LOCAL (Mock) Environment Configuration
# =============================================================================
# Use this profile for local development with Docker containers
# Run with: MIX_ENV=local mix phx.server
# =============================================================================

import Config

config :call_service, CallService.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: 4002],
  check_origin: false,
  debug_errors: true,
  code_reloader: false,
  secret_key_base: "local_dev_secret_key_base_call_service_quckapp_32_chars"

# MongoDB - Local Docker
config :call_service, :mongodb,
  url: "mongodb://localhost:27017/quckapp_calls_local",
  pool_size: 5

# Redis - Local Docker
config :call_service, :redis,
  host: "localhost",
  port: 6379,
  password: nil,
  database: 4

# Kafka - Local Docker
config :call_service, :kafka,
  brokers: [{"localhost", 9092}],
  consumer_group: "call-service-local"

# JWT - Same secret as auth-service local
config :call_service, CallService.Guardian,
  issuer: "quckapp-auth-local",
  secret_key: "bG9jYWwtZGV2LXNlY3JldC1rZXktZm9yLXRlc3Rpbmctb25seS0zMi1jaGFycw=="

# ICE/TURN servers - Only STUN for local
config :call_service, :ice_servers, [
  %{urls: "stun:stun.l.google.com:19302"},
  %{urls: "stun:stun1.l.google.com:19302"}
]

# Services
config :call_service, :services,
  auth_service_url: "http://localhost:8081",
  user_service_url: "http://localhost:8082"

# Logging - Verbose for local
config :logger, :console,
  format: "[$level] $message\n",
  level: :debug
