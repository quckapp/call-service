import Config

config :call_service, namespace: CallService

config :call_service, CallService.Endpoint,
  url: [host: "localhost"],
  render_errors: [formats: [json: CallService.ErrorJSON], layout: false],
  pubsub_server: CallService.PubSub

config :call_service, :mongodb,
  url: System.get_env("MONGODB_URI") || "mongodb://localhost:27017/quckchat_calls",
  pool_size: 10

config :call_service, :redis,
  host: System.get_env("REDIS_HOST") || "localhost",
  port: String.to_integer(System.get_env("REDIS_PORT") || "6379"),
  database: 4

config :call_service, :kafka,
  brokers: [System.get_env("KAFKA_BROKER") || "localhost:9092"],
  consumer_group: "call-service-group"

config :call_service, CallService.Guardian,
  issuer: "quckchat",
  secret_key: System.get_env("JWT_SECRET") || "your-secret-key"

config :call_service, :ice_servers, [
  %{urls: "stun:stun.l.google.com:19302"},
  %{urls: "stun:stun1.l.google.com:19302"}
]

config :libcluster, topologies: [call_cluster: [strategy: Cluster.Strategy.Gossip]]
config :logger, :console, format: "$time $metadata[$level] $message\n", metadata: [:request_id, :call_id]
config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
