defmodule CallService.Application do
  @moduledoc """
  Call Service Application - Manages voice/video calls and WebRTC signaling.
  Supports 1:1 calls, group calls, and huddle sessions.
  """
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      CallService.Telemetry,
      {Phoenix.PubSub, name: CallService.PubSub},
      {Mongo, [
        name: :call_mongo,
        url: Application.get_env(:call_service, :mongodb)[:url],
        pool_size: Application.get_env(:call_service, :mongodb)[:pool_size] || 10
      ]},
      {Redix, [
        host: Application.get_env(:call_service, :redis)[:host],
        port: Application.get_env(:call_service, :redis)[:port],
        database: Application.get_env(:call_service, :redis)[:database] || 4,
        name: :call_redis
      ]},
      {Horde.Registry, [name: CallService.CallRegistry, keys: :unique]},
      {Horde.DynamicSupervisor, [name: CallService.CallSupervisor, strategy: :one_for_one]},
      CallService.CallManager,
      CallService.HuddleManager,
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
