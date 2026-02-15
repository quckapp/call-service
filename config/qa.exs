# =============================================================================
# QA Environment Configuration
# =============================================================================
# Use this profile for QA environment
# Run with: MIX_ENV=qa mix phx.server
# =============================================================================

import Config

config :call_service, CallService.Endpoint,
  http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}, port: String.to_integer(System.get_env("PORT") || "4002")],
  url: [host: System.get_env("PHX_HOST") || "localhost", port: 443, scheme: "https"],
  secret_key_base: System.get_env("SECRET_KEY_BASE"),
  server: true

# MongoDB - QA
config :call_service, :mongodb,
  url: System.get_env("MONGODB_URI"),
  pool_size: String.to_integer(System.get_env("MONGODB_POOL_SIZE") || "15")

# Redis - QA
config :call_service, :redis,
  host: System.get_env("REDIS_HOST"),
  port: String.to_integer(System.get_env("REDIS_PORT") || "6379"),
  password: System.get_env("REDIS_PASSWORD"),
  database: String.to_integer(System.get_env("REDIS_DATABASE") || "4")

# Kafka - QA
config :call_service, :kafka,
  brokers: [System.get_env("KAFKA_BROKER") || "localhost:9092"],
  consumer_group: "call-service-qa"

# JWT
config :call_service, CallService.Guardian,
  issuer: "quckapp-auth",
  secret_key: System.get_env("JWT_SECRET")

# ICE/TURN servers
config :call_service, :ice_servers, [
  %{urls: "stun:stun.l.google.com:19302"},
  %{urls: "stun:stun1.l.google.com:19302"},
  %{
    urls: System.get_env("TURN_SERVER_URL"),
    username: System.get_env("TURN_USERNAME"),
    credential: System.get_env("TURN_CREDENTIAL")
  }
]

# Services
config :call_service, :services,
  auth_service_url: System.get_env("AUTH_SERVICE_URL"),
  user_service_url: System.get_env("USER_SERVICE_URL")

# Logging - Info level for QA
config :logger, level: :info
