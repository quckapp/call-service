import Config

if config_env() == :prod do
  config :call_service, CallService.Endpoint,
    url: [host: System.get_env("PHX_HOST") || "localhost", port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}, port: String.to_integer(System.get_env("PORT") || "4002")],
    secret_key_base: System.get_env("SECRET_KEY_BASE") || raise("SECRET_KEY_BASE missing")

  config :call_service, :mongodb,
    url: System.get_env("MONGODB_URI") || raise("MONGODB_URI missing"),
    pool_size: String.to_integer(System.get_env("MONGODB_POOL_SIZE") || "20")

  config :call_service, :redis,
    host: System.get_env("REDIS_HOST"),
    port: String.to_integer(System.get_env("REDIS_PORT") || "6379"),
    password: System.get_env("REDIS_PASSWORD")

  config :call_service, CallService.Guardian, secret_key: System.get_env("JWT_SECRET")

  # TURN server configuration for production
  config :call_service, :ice_servers, [
    %{urls: "stun:stun.l.google.com:19302"},
    %{
      urls: System.get_env("TURN_SERVER_URL"),
      username: System.get_env("TURN_USERNAME"),
      credential: System.get_env("TURN_CREDENTIAL")
    }
  ]
end
