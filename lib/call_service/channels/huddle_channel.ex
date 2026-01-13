defmodule CallService.HuddleChannel do
  use Phoenix.Channel
  require Logger

  @impl true
  def join("huddle:" <> huddle_id, _params, socket) do
    user_id = socket.assigns.user_id
    case CallService.HuddleManager.get_huddle(huddle_id) do
      {:ok, nil} -> {:error, %{reason: "Huddle not found"}}
      {:ok, huddle} ->
        Phoenix.PubSub.subscribe(CallService.PubSub, "channel:#{huddle.channel_id}")
        Logger.info("User #{user_id} joined huddle channel #{huddle_id}")
        {:ok, %{huddle: huddle}, assign(socket, :huddle_id, huddle_id)}
    end
  end

  @impl true
  def handle_in("offer", %{"to_user_id" => to_user_id, "sdp" => sdp}, socket) do
    push_to_user(to_user_id, "offer", %{from: socket.assigns.user_id, sdp: sdp})
    {:reply, :ok, socket}
  end

  @impl true
  def handle_in("answer", %{"to_user_id" => to_user_id, "sdp" => sdp}, socket) do
    push_to_user(to_user_id, "answer", %{from: socket.assigns.user_id, sdp: sdp})
    {:reply, :ok, socket}
  end

  @impl true
  def handle_in("ice_candidate", %{"to_user_id" => to_user_id, "candidate" => candidate}, socket) do
    push_to_user(to_user_id, "ice_candidate", %{from: socket.assigns.user_id, candidate: candidate})
    {:reply, :ok, socket}
  end

  @impl true
  def handle_in("mute", %{"muted" => muted}, socket) do
    CallService.HuddleManager.toggle_mute(socket.assigns.huddle_id, socket.assigns.user_id, muted)
    {:reply, :ok, socket}
  end

  @impl true
  def handle_in("video", %{"enabled" => enabled}, socket) do
    CallService.HuddleManager.toggle_video(socket.assigns.huddle_id, socket.assigns.user_id, enabled)
    {:reply, :ok, socket}
  end

  @impl true
  def handle_info({:huddle_participant_joined, huddle_id, user_id, participant}, socket) do
    push(socket, "participant_joined", %{huddle_id: huddle_id, user_id: user_id, participant: participant})
    {:noreply, socket}
  end

  @impl true
  def handle_info({:huddle_participant_left, huddle_id, user_id}, socket) do
    push(socket, "participant_left", %{huddle_id: huddle_id, user_id: user_id})
    {:noreply, socket}
  end

  @impl true
  def handle_info({:huddle_participant_updated, huddle_id, user_id, changes}, socket) do
    push(socket, "participant_updated", %{huddle_id: huddle_id, user_id: user_id, changes: changes})
    {:noreply, socket}
  end

  @impl true
  def handle_info({:huddle_ended, huddle_id}, socket) do
    push(socket, "huddle_ended", %{huddle_id: huddle_id})
    {:noreply, socket}
  end

  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}

  defp push_to_user(user_id, event, payload) do
    Phoenix.PubSub.broadcast(CallService.PubSub, "user:#{user_id}:huddle", {event, payload})
  end
end
