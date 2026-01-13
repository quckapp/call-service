defmodule CallService.Actors.CallSession do
  @moduledoc """
  Call Session Actor - Manages individual call state and WebRTC signaling.
  Each active call has its own supervised process.
  """
  use GenServer, restart: :transient
  require Logger

  @call_timeout 3600_000  # 1 hour max call duration
  @ringing_timeout 60_000  # 60 seconds to answer

  defstruct [:call_id, :call, :timer_ref, :state]

  # Client API

  def start_link(opts) do
    call = Keyword.fetch!(opts, :call)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(call.call_id))
  end

  def via_tuple(call_id), do: {:via, Horde.Registry, {CallService.CallRegistry, call_id}}

  def get_state(call_id), do: GenServer.call(via_tuple(call_id), :get_state)
  
  def send_offer(call_id, from_user_id, sdp_offer) do
    GenServer.cast(via_tuple(call_id), {:offer, from_user_id, sdp_offer})
  end

  def send_answer(call_id, from_user_id, sdp_answer) do
    GenServer.cast(via_tuple(call_id), {:answer, from_user_id, sdp_answer})
  end

  def send_ice(call_id, from_user_id, candidate) do
    GenServer.cast(via_tuple(call_id), {:ice, from_user_id, candidate})
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    call = Keyword.fetch!(opts, :call)
    timer_ref = Process.send_after(self(), :ringing_timeout, @ringing_timeout)
    
    Logger.info("Call session started for #{call.call_id}")
    {:ok, %__MODULE__{call_id: call.call_id, call: call, timer_ref: timer_ref, state: :ringing}}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, {:ok, state}, state}
  end

  @impl true
  def handle_cast({:offer, from_user_id, sdp_offer}, state) do
    # Forward offer to other participants
    broadcast_to_others(state.call, from_user_id, {:sdp_offer, state.call_id, from_user_id, sdp_offer})
    {:noreply, state}
  end

  @impl true
  def handle_cast({:answer, from_user_id, sdp_answer}, state) do
    # Cancel ringing timeout and set call timeout
    if state.timer_ref, do: Process.cancel_timer(state.timer_ref)
    new_timer = Process.send_after(self(), :call_timeout, @call_timeout)
    
    broadcast_to_others(state.call, from_user_id, {:sdp_answer, state.call_id, from_user_id, sdp_answer})
    {:noreply, %{state | state: :active, timer_ref: new_timer}}
  end

  @impl true
  def handle_cast({:ice, from_user_id, candidate}, state) do
    broadcast_to_others(state.call, from_user_id, {:ice_candidate, state.call_id, from_user_id, candidate})
    {:noreply, state}
  end

  @impl true
  def handle_info(:ringing_timeout, state) do
    Logger.info("Call #{state.call_id} timed out (no answer)")
    # Notify all participants
    Enum.each(Map.keys(state.call.participants), fn user_id ->
      Phoenix.PubSub.broadcast(CallService.PubSub, "user:#{user_id}", {:call_timeout, state.call_id})
    end)
    {:stop, :normal, state}
  end

  @impl true
  def handle_info(:call_timeout, state) do
    Logger.info("Call #{state.call_id} reached maximum duration")
    Enum.each(Map.keys(state.call.participants), fn user_id ->
      Phoenix.PubSub.broadcast(CallService.PubSub, "user:#{user_id}", {:call_max_duration, state.call_id})
    end)
    {:stop, :normal, state}
  end

  @impl true
  def terminate(_reason, state) do
    Logger.info("Call session terminated for #{state.call_id}")
    :ok
  end

  # Private Functions

  defp broadcast_to_others(call, from_user_id, message) do
    Enum.each(Map.keys(call.participants), fn user_id ->
      if user_id != from_user_id do
        Phoenix.PubSub.broadcast(CallService.PubSub, "user:#{user_id}", message)
      end
    end)
  end
end
