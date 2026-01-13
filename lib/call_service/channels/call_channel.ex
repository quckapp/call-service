defmodule CallService.CallChannel do
  use Phoenix.Channel
  require Logger

  @impl true
  def join("call:" <> call_id, _params, socket) do
    user_id = socket.assigns.user_id
    Phoenix.PubSub.subscribe(CallService.PubSub, "user:#{user_id}")
    Logger.info("User #{user_id} joined call channel #{call_id}")
    {:ok, socket |> assign(:call_id, call_id)}
  end

  @impl true
  def handle_in("offer", %{"sdp" => sdp}, socket) do
    CallService.Actors.CallSession.send_offer(socket.assigns.call_id, socket.assigns.user_id, sdp)
    {:reply, :ok, socket}
  end

  @impl true
  def handle_in("answer", %{"sdp" => sdp}, socket) do
    CallService.Actors.CallSession.send_answer(socket.assigns.call_id, socket.assigns.user_id, sdp)
    {:reply, :ok, socket}
  end

  @impl true
  def handle_in("ice_candidate", %{"candidate" => candidate}, socket) do
    CallService.Actors.CallSession.send_ice(socket.assigns.call_id, socket.assigns.user_id, candidate)
    {:reply, :ok, socket}
  end

  @impl true
  def handle_info({:sdp_offer, call_id, from_user_id, sdp}, socket) do
    push(socket, "offer", %{call_id: call_id, from: from_user_id, sdp: sdp})
    {:noreply, socket}
  end

  @impl true
  def handle_info({:sdp_answer, call_id, from_user_id, sdp}, socket) do
    push(socket, "answer", %{call_id: call_id, from: from_user_id, sdp: sdp})
    {:noreply, socket}
  end

  @impl true
  def handle_info({:ice_candidate, call_id, from_user_id, candidate}, socket) do
    push(socket, "ice_candidate", %{call_id: call_id, from: from_user_id, candidate: candidate})
    {:noreply, socket}
  end

  @impl true
  def handle_info({:incoming_call, call}, socket) do
    push(socket, "incoming_call", %{call: call})
    {:noreply, socket}
  end

  @impl true
  def handle_info({:call_ended, call_id, ender_id}, socket) do
    push(socket, "call_ended", %{call_id: call_id, ended_by: ender_id})
    {:noreply, socket}
  end

  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}
end
