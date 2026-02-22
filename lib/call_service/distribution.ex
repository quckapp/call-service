defmodule CallService.Distribution do
  @moduledoc """
  Consistent hashing for call service using ex_hash_ring.

  Provides consistent distribution of:
  - Call sessions across nodes
  - Redis pool connections
  - Kafka partition selection

  Consistent hashing ensures that:
  - The same call_id always routes to the same node/partition
  - Adding/removing nodes only affects ~1/n of the keys
  - Load is evenly distributed across nodes

  ## Usage:

      # Get the Redis pool connection for a call
      pool_idx = Distribution.get_redis_pool(call_id)

      # Get the Kafka partition for a user
      partition = Distribution.get_partition(user_id, partition_count)

      # Get the node for handling a call
      node = Distribution.get_node(call_id)
  """

  use GenServer
  require Logger

  @default_replicas 256
  @default_pool_size 5
  @default_partition_count 3

  # Ring names
  @redis_ring CallService.Distribution.RedisRing
  @partition_ring CallService.Distribution.PartitionRing
  @node_ring CallService.Distribution.NodeRing

  # ============================================================================
  # Public API
  # ============================================================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get the Redis pool index for a given key.
  Ensures consistent mapping of keys to pool connections.
  """
  def get_redis_pool(key) do
    case ExHashRing.Ring.find_node(@redis_ring, to_string(key)) do
      {:ok, pool_idx} -> pool_idx
      _ -> :rand.uniform(pool_size()) - 1
    end
  end

  @doc """
  Get the Kafka partition for a given key.
  Ensures consistent mapping of keys to partitions.
  """
  def get_partition(key, partition_count \\ @default_partition_count) do
    # For non-default partition counts, use hash modulo
    if partition_count != @default_partition_count do
      :erlang.phash2(key, partition_count)
    else
      case ExHashRing.Ring.find_node(@partition_ring, to_string(key)) do
        {:ok, partition} -> partition
        _ -> :erlang.phash2(key, partition_count)
      end
    end
  end

  @doc """
  Get the node that should handle a given key.
  Used for distributed call session placement.
  """
  def get_node(key) do
    case ExHashRing.Ring.find_node(@node_ring, to_string(key)) do
      {:ok, node_name} -> node_name
      _ -> node()
    end
  end

  @doc """
  Add a node to the ring.
  """
  def add_node(node_name) do
    case ExHashRing.Ring.add_node(@node_ring, node_name) do
      :ok ->
        Logger.info("[Distribution] Added node: #{node_name}")
        :ok
      error ->
        Logger.warning("[Distribution] Failed to add node #{node_name}: #{inspect(error)}")
        error
    end
  end

  @doc """
  Remove a node from the ring.
  """
  def remove_node(node_name) do
    case ExHashRing.Ring.remove_node(@node_ring, node_name) do
      :ok ->
        Logger.info("[Distribution] Removed node: #{node_name}")
        :ok
      error ->
        Logger.warning("[Distribution] Failed to remove node #{node_name}: #{inspect(error)}")
        error
    end
  end

  @doc """
  Get the current ring status.
  """
  def status do
    nodes = case ExHashRing.Ring.get_nodes(@node_ring) do
      {:ok, nodes} -> nodes
      _ -> []
    end

    %{
      nodes: nodes,
      redis_pools: pool_size(),
      partitions: @default_partition_count,
      replicas: @default_replicas
    }
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl true
  def init(_opts) do
    # Start the hash rings as child processes
    start_rings()

    # Subscribe to node up/down events
    :net_kernel.monitor_nodes(true)

    Logger.info("[Distribution] Initialized with #{@default_replicas} replicas")

    {:ok, %{}}
  end

  @impl true
  def handle_info({:nodeup, node_name}, state) do
    add_node(node_name)
    {:noreply, state}
  end

  @impl true
  def handle_info({:nodedown, node_name}, state) do
    remove_node(node_name)
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp start_rings do
    # Redis pool ring
    pool_nodes = for i <- 0..(pool_size() - 1), do: i
    start_ring(@redis_ring, pool_nodes)

    # Partition ring
    partition_nodes = for i <- 0..(@default_partition_count - 1), do: i
    start_ring(@partition_ring, partition_nodes)

    # Node ring with current cluster nodes
    cluster_nodes = [node() | Node.list()]
    start_ring(@node_ring, cluster_nodes)
  end

  defp start_ring(name, nodes) do
    case ExHashRing.Ring.start_link(
      name: name,
      nodes: nodes,
      replicas: @default_replicas
    ) do
      {:ok, _pid} ->
        Logger.debug("[Distribution] Started ring #{name} with nodes: #{inspect(nodes)}")
        :ok
      {:error, {:already_started, _pid}} ->
        # Ring already exists, update nodes
        ExHashRing.Ring.set_nodes(name, nodes)
        :ok
      error ->
        Logger.error("[Distribution] Failed to start ring #{name}: #{inspect(error)}")
        error
    end
  end

  defp pool_size do
    Application.get_env(:call_service, :redis_pool_size, @default_pool_size)
  end
end
