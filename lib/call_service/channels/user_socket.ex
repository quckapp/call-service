defmodule CallService.UserSocket do
  use Phoenix.Socket

  channel "call:*", CallService.CallChannel
  channel "huddle:*", CallService.HuddleChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    case CallService.Guardian.decode_and_verify(token) do
      {:ok, claims} -> {:ok, assign(socket, :user_id, claims["sub"])}
      {:error, _} -> :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(socket), do: "user_socket:#{socket.assigns.user_id}"
end
