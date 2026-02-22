defmodule CallService.Application do
  @moduledoc """
  Call Service Application - Manages voice/video calls and WebRTC signaling.
  Supports 1:1 calls, group calls, and huddle sessions.
  """
  use Application

  @impl true
  def start(_type, _args) do
    # Initialize circuit breakers
    CallService.CircuitBreaker.init()

    children = [
      CallService.Telemetry,
      {Phoenix.PubSub, name: CallService.PubSub},
      {Mongo, [
        name: :call_mongo,
        url: Application.get_env(:call_service, :mongodb)[:url],
        pool_size: Application.get_env(:call_service, :mongodb)[:pool_size] || 10
      ]},
      {Redix,
        [
          host: Application.get_env(:call_service, :redis)[:host],
          port: Application.get_env(:call_service, :redis)[:port],
          database: Application.get_env(:call_service, :redis)[:database] || 4,
          name: :call_redis
        ] ++ if(Application.get_env(:call_service, :redis)[:password],
          do: [password: Application.get_env(:call_service, :redis)[:password]],
          else: []
        )},
      {Horde.Registry, [name: CallService.CallRegistry, keys: :unique]},
      {Horde.DynamicSupervisor, [name: CallService.CallSupervisor, strategy: :one_for_one]},
      # Hash ring for consistent distribution
      CallService.Distribution,
      CallService.CallManager,
      CallService.HuddleManager,
      CallService.Kafka.Producer,
      CallService.Kafka.Consumer,
      {Cluster.Supervisor, [Application.get_env(:libcluster, :topologies), [name: CallService.ClusterSupervisor]]},
      CallService.Endpoint
    ]

    opts = [strategy: :one_for_one, name: CallService.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    CallService.Endpoint.config_change(changed, removed)
    :ok
  end
end
