defmodule CallService.HuddleController do
  use Phoenix.Controller, formats: [:json]

  def create(conn, %{"channel_id" => channel_id, "name" => name} = params) do
    user_id = conn.assigns[:current_user_id]
    settings = Map.get(params, "settings", %{})
    case CallService.HuddleManager.create_huddle(user_id, channel_id, name, settings) do
      {:ok, huddle} -> json(conn, %{success: true, data: huddle})
      {:error, reason} -> conn |> put_status(400) |> json(%{success: false, error: reason})
    end
  end

  def join(conn, %{"huddle_id" => huddle_id} = params) do
    user_id = conn.assigns[:current_user_id]
    metadata = Map.get(params, "metadata", %{})
    case CallService.HuddleManager.join_huddle(huddle_id, user_id, metadata) do
      {:ok, huddle} -> json(conn, %{success: true, data: huddle})
      {:error, reason} -> conn |> put_status(400) |> json(%{success: false, error: reason})
    end
  end

  def leave(conn, %{"huddle_id" => huddle_id}) do
    user_id = conn.assigns[:current_user_id]
    case CallService.HuddleManager.leave_huddle(huddle_id, user_id) do
      {:ok, result} -> json(conn, %{success: true, data: result})
      {:error, reason} -> conn |> put_status(400) |> json(%{success: false, error: reason})
    end
  end

  def end_huddle(conn, %{"huddle_id" => huddle_id}) do
    user_id = conn.assigns[:current_user_id]
    case CallService.HuddleManager.end_huddle(huddle_id, user_id) do
      {:ok, _} -> json(conn, %{success: true, message: "Huddle ended"})
      {:error, reason} -> conn |> put_status(400) |> json(%{success: false, error: reason})
    end
  end

  def show(conn, %{"huddle_id" => huddle_id}) do
    case CallService.HuddleManager.get_huddle(huddle_id) do
      {:ok, nil} -> conn |> put_status(404) |> json(%{success: false, error: "Huddle not found"})
      {:ok, huddle} -> json(conn, %{success: true, data: huddle})
    end
  end

  def channel_huddles(conn, %{"channel_id" => channel_id}) do
    {:ok, huddles} = CallService.HuddleManager.get_channel_huddles(channel_id)
    json(conn, %{success: true, data: huddles})
  end

  def toggle_mute(conn, %{"huddle_id" => huddle_id, "muted" => muted}) do
    user_id = conn.assigns[:current_user_id]
    CallService.HuddleManager.toggle_mute(huddle_id, user_id, muted)
    json(conn, %{success: true})
  end

  def toggle_video(conn, %{"huddle_id" => huddle_id, "enabled" => enabled}) do
    user_id = conn.assigns[:current_user_id]
    CallService.HuddleManager.toggle_video(huddle_id, user_id, enabled)
    json(conn, %{success: true})
  end
end
