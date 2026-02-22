# =============================================================================
# LIVE Environment Configuration
# =============================================================================
# Use this profile for live environment (same as production with stricter settings)
# Run with: MIX_ENV=live mix phx.server
# =============================================================================

import Config

config :call_service, CallService.Endpoint,
  http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}, port: String.to_integer(System.get_env("PORT") || "4002")],
  url: [host: System.get_env("PHX_HOST") || "localhost", port: 443, scheme: "https"],
  secret_key_base: System.get_env("SECRET_KEY_BASE") || raise("SECRET_KEY_BASE missing"),
  server: true,
  cache_static_manifest: "priv/static/cache_manifest.json"

# MongoDB - Live (highest pool size)
config :call_service, :mongodb,
  url: System.get_env("MONGODB_URI") || raise("MONGODB_URI missing"),
  pool_size: String.to_integer(System.get_env("MONGODB_POOL_SIZE") || "100"),
  timeout: 15_000,
  connect_timeout: 10_000

# Redis - Live
config :call_service, :redis,
  host: System.get_env("REDIS_HOST") || raise("REDIS_HOST missing"),
  port: String.to_integer(System.get_env("REDIS_PORT") || "6379"),
  password: System.get_env("REDIS_PASSWORD"),
  database: String.to_integer(System.get_env("REDIS_DATABASE") || "4"),
  pool_size: 64,
  ssl: System.get_env("REDIS_SSL") == "true"

# Kafka - Live
config :call_service, :kafka,
  brokers: String.split(System.get_env("KAFKA_BROKERS") || "localhost:9092", ","),
  consumer_group: "call-service-live",
  ssl: System.get_env("KAFKA_SSL") == "true"

# JWT
config :call_service, CallService.Guardian,
  issuer: "quckapp-auth",
  secret_key: System.get_env("JWT_SECRET") || raise("JWT_SECRET missing")

# ICE/TURN servers - Full TURN configuration for NAT traversal
config :call_service, :ice_servers, [
  %{urls: "stun:stun.l.google.com:19302"},
  %{urls: "stun:stun1.l.google.com:19302"},
  %{urls: "stun:stun2.l.google.com:19302"},
  %{urls: "stun:stun3.l.google.com:19302"},
  %{
    urls: System.get_env("TURN_SERVER_URL") || raise("TURN_SERVER_URL missing"),
    username: System.get_env("TURN_USERNAME"),
    credential: System.get_env("TURN_CREDENTIAL")
  }
]

# Services
config :call_service, :services,
  auth_service_url: System.get_env("AUTH_SERVICE_URL") || raise("AUTH_SERVICE_URL missing"),
  user_service_url: System.get_env("USER_SERVICE_URL") || raise("USER_SERVICE_URL missing")

# Logging - Error level only for live
config :logger, level: :error
