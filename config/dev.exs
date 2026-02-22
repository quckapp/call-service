import Config

config :call_service, CallService.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: 4002],
  check_origin: false, debug_errors: true,
  secret_key_base: "dev_secret_key_base_call_service_quckapp",
  watchers: []

# MongoDB configuration for development
config :call_service, :mongodb,
  url: "mongodb://localhost:27017/quckapp_calls_dev",
  pool_size: 5

# Redis configuration for development
config :call_service, :redis,
  host: "localhost",
  port: 6379,
  database: 1

# Kafka configuration for development (disabled by default)
config :call_service, :kafka,
  enabled: false,
  brokers: [{~c"localhost", 9092}],
  consumer_group: "call-service-group-dev"

# Guardian JWT configuration for development
config :call_service, CallService.Guardian,
  issuer: "call_service",
  secret_key: "dev_jwt_secret_for_call_service"

# libcluster topology for development (no clustering)
config :libcluster, topologies: []

config :logger, :console, format: "[$level] $message\n"
config :phoenix, :plug_init_mode, :runtime
