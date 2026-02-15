import Config

# Runtime configuration for all environments
# These settings are applied at runtime when the application starts

# Helper function to parse Redis URL
defmodule ConfigHelpers do
  def parse_redis_url(nil), do: nil
  def parse_redis_url(url) do
    uri = URI.parse(url)
    password = if uri.userinfo, do: String.split(uri.userinfo, ":") |> List.last(), else: nil
    %{
      host: uri.host || "localhost",
      port: uri.port || 6379,
      password: password
    }
  end

  def parse_kafka_brokers(nil), do: nil
  def parse_kafka_brokers(brokers_string) do
    brokers_string
    |> String.split(",")
    |> Enum.map(fn broker ->
      [host, port] = String.split(String.trim(broker), ":")
      {String.to_charlist(host), String.to_integer(port)}
    end)
  end
end

# Common configuration for all environments
config :call_service, CallService.Endpoint,
  url: [host: System.get_env("PHX_HOST") || "localhost"],
  http: [
    ip: {0, 0, 0, 0, 0, 0, 0, 0},
    port: String.to_integer(System.get_env("PORT") || "4002")
  ],
  server: true

# MongoDB configuration
if mongodb_url = System.get_env("MONGODB_URL") || System.get_env("MONGODB_URI") do
  config :call_service, :mongodb,
    url: mongodb_url,
    pool_size: String.to_integer(System.get_env("MONGODB_POOL_SIZE") || "20")
end

# Redis configuration - supports both URL and individual parameters
if redis_url = System.get_env("REDIS_URL") do
  redis_config = ConfigHelpers.parse_redis_url(redis_url)
  config :call_service, :redis,
    host: redis_config.host,
    port: redis_config.port,
    password: redis_config.password
else
  if System.get_env("REDIS_HOST") do
    config :call_service, :redis,
      host: System.get_env("REDIS_HOST"),
      port: String.to_integer(System.get_env("REDIS_PORT") || "6379"),
      password: System.get_env("REDIS_PASSWORD")
  end
end

# Kafka configuration
kafka_enabled = System.get_env("KAFKA_ENABLED", "false") == "true"
kafka_brokers = System.get_env("KAFKA_BROKERS")

config :call_service, :kafka,
  enabled: kafka_enabled,
  brokers: if(kafka_brokers, do: ConfigHelpers.parse_kafka_brokers(kafka_brokers), else: []),
  consumer_group: System.get_env("KAFKA_CONSUMER_GROUP") || "call-service-group",
  client_id: :call_service_kafka_client

# Auth service configuration
if auth_service_url = System.get_env("AUTH_SERVICE_URL") do
  config :call_service, :auth_service,
    url: auth_service_url
end

# Database URL (PostgreSQL) for future use
if database_url = System.get_env("DATABASE_URL") do
  config :call_service, CallService.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")
end

# Production-specific configuration
if config_env() == :prod do
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  config :call_service, CallService.Endpoint,
    url: [host: System.get_env("PHX_HOST") || "localhost", port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}, port: String.to_integer(System.get_env("PORT") || "4002")],
    secret_key_base: secret_key_base

  # Guardian JWT configuration
  config :call_service, CallService.Guardian,
    secret_key: System.get_env("JWT_SECRET") || secret_key_base

  # TURN server configuration for production
  config :call_service, :ice_servers, [
    %{urls: "stun:stun.l.google.com:19302"},
    %{
      urls: System.get_env("TURN_SERVER_URL"),
      username: System.get_env("TURN_USERNAME"),
      credential: System.get_env("TURN_CREDENTIAL")
    }
  ]

  # Jaeger/OpenTelemetry tracing configuration
  if jaeger_endpoint = System.get_env("JAEGER_ENDPOINT") do
    config :call_service, :tracing,
      endpoint: jaeger_endpoint,
      service_name: "call-service"
  end

  # Erlang distribution cookie for clustering
  if release_cookie = System.get_env("RELEASE_COOKIE") do
    config :call_service, :cluster,
      cookie: String.to_atom(release_cookie)
  end
end

# Development/test configuration
if config_env() in [:dev, :test] do
  config :call_service, CallService.Endpoint,
    secret_key_base: System.get_env("SECRET_KEY_BASE") || "dev_secret_key_base_that_is_at_least_64_bytes_long_for_development_only"

  config :call_service, CallService.Guardian,
    secret_key: System.get_env("JWT_SECRET") || "dev_jwt_secret_for_testing"

  # Development ICE servers (STUN only)
  config :call_service, :ice_servers, [
    %{urls: "stun:stun.l.google.com:19302"},
    %{urls: "stun:stun1.l.google.com:19302"}
  ]
end
