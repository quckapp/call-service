defmodule CallService.HuddleController do
  use Phoenix.Controller, formats: [:json]
  use OpenApiSpex.ControllerSpecs

  alias CallService.Schemas.Huddle
  alias CallService.Schemas.Common

  tags ["Huddles"]
  security [%{"bearer_auth" => []}]

  operation :create,
    summary: "Create a huddle",
    description: "Creates a new huddle in a channel",
    request_body: {"Huddle creation request", "application/json", Huddle.HuddleRequest},
    responses: [
      ok: {"Huddle created successfully", "application/json", Huddle.HuddleResponse},
      bad_request: {"Invalid request", "application/json", Common.ErrorResponse},
      unauthorized: {"Authentication required", "application/json", Common.ErrorResponse}
    ]

  def create(conn, %{"channel_id" => channel_id, "name" => name} = params) do
    user_id = conn.assigns[:current_user_id]
    settings = Map.get(params, "settings", %{})
    case CallService.HuddleManager.create_huddle(user_id, channel_id, name, settings) do
      {:ok, huddle} -> json(conn, %{success: true, data: huddle})
      {:error, reason} -> conn |> put_status(400) |> json(%{success: false, error: reason})
    end
  end

  operation :join,
    summary: "Join a huddle",
    description: "Joins an existing huddle",
    parameters: [
      huddle_id: [in: :path, description: "Huddle ID", type: :string, required: true]
    ],
    request_body: {"Join huddle request", "application/json", Huddle.JoinHuddleRequest},
    responses: [
      ok: {"Successfully joined huddle", "application/json", Huddle.HuddleResponse},
      bad_request: {"Invalid request or huddle state", "application/json", Common.ErrorResponse},
      unauthorized: {"Authentication required", "application/json", Common.ErrorResponse}
    ]

  def join(conn, %{"huddle_id" => huddle_id} = params) do
    user_id = conn.assigns[:current_user_id]
    metadata = Map.get(params, "metadata", %{})
    case CallService.HuddleManager.join_huddle(huddle_id, user_id, metadata) do
      {:ok, huddle} -> json(conn, %{success: true, data: huddle})
      {:error, reason} -> conn |> put_status(400) |> json(%{success: false, error: reason})
    end
  end

  operation :leave,
    summary: "Leave a huddle",
    description: "Leaves an active huddle",
    parameters: [
      huddle_id: [in: :path, description: "Huddle ID", type: :string, required: true]
    ],
    responses: [
      ok: {"Successfully left huddle", "application/json", Huddle.LeaveHuddleResponse},
      bad_request: {"Invalid request or huddle state", "application/json", Common.ErrorResponse},
      unauthorized: {"Authentication required", "application/json", Common.ErrorResponse}
    ]

  def leave(conn, %{"huddle_id" => huddle_id}) do
    user_id = conn.assigns[:current_user_id]
    case CallService.HuddleManager.leave_huddle(huddle_id, user_id) do
      {:ok, result} -> json(conn, %{success: true, data: result})
      {:error, reason} -> conn |> put_status(400) |> json(%{success: false, error: reason})
    end
  end

  operation :end_huddle,
    summary: "End a huddle",
    description: "Ends an active huddle (host only)",
    parameters: [
      huddle_id: [in: :path, description: "Huddle ID", type: :string, required: true]
    ],
    responses: [
      ok: {"Huddle ended successfully", "application/json", Common.SuccessResponse},
      bad_request: {"Invalid request or not authorized", "application/json", Common.ErrorResponse},
      unauthorized: {"Authentication required", "application/json", Common.ErrorResponse}
    ]

  def end_huddle(conn, %{"huddle_id" => huddle_id}) do
    user_id = conn.assigns[:current_user_id]
    case CallService.HuddleManager.end_huddle(huddle_id, user_id) do
      {:ok, _} -> json(conn, %{success: true, message: "Huddle ended"})
      {:error, reason} -> conn |> put_status(400) |> json(%{success: false, error: reason})
    end
  end

  operation :show,
    summary: "Get huddle details",
    description: "Retrieves details of a specific huddle",
    parameters: [
      huddle_id: [in: :path, description: "Huddle ID", type: :string, required: true]
    ],
    responses: [
      ok: {"Huddle details", "application/json", Huddle.HuddleResponse},
      not_found: {"Huddle not found", "application/json", Common.ErrorResponse},
      unauthorized: {"Authentication required", "application/json", Common.ErrorResponse}
    ]

  def show(conn, %{"huddle_id" => huddle_id}) do
    case CallService.HuddleManager.get_huddle(huddle_id) do
      {:ok, nil} -> conn |> put_status(404) |> json(%{success: false, error: "Huddle not found"})
      {:ok, huddle} -> json(conn, %{success: true, data: huddle})
    end
  end

  operation :channel_huddles,
    summary: "Get channel huddles",
    description: "Retrieves all active huddles in a channel",
    parameters: [
      channel_id: [in: :path, description: "Channel ID", type: :string, required: true]
    ],
    responses: [
      ok: {"List of huddles in channel", "application/json", Huddle.HuddleListResponse},
      unauthorized: {"Authentication required", "application/json", Common.ErrorResponse}
    ]

  def channel_huddles(conn, %{"channel_id" => channel_id}) do
    {:ok, huddles} = CallService.HuddleManager.get_channel_huddles(channel_id)
    json(conn, %{success: true, data: huddles})
  end

  operation :toggle_mute,
    summary: "Toggle mute status",
    description: "Toggles the mute status for the authenticated user in a huddle",
    parameters: [
      huddle_id: [in: :path, description: "Huddle ID", type: :string, required: true]
    ],
    request_body: {"Mute toggle request", "application/json", Huddle.MuteRequest},
    responses: [
      ok: {"Mute status toggled", "application/json", Common.SuccessResponse},
      bad_request: {"Invalid request", "application/json", Common.ErrorResponse},
      unauthorized: {"Authentication required", "application/json", Common.ErrorResponse}
    ]

  def toggle_mute(conn, %{"huddle_id" => huddle_id, "muted" => muted}) do
    user_id = conn.assigns[:current_user_id]
    CallService.HuddleManager.toggle_mute(huddle_id, user_id, muted)
    json(conn, %{success: true})
  end

  operation :toggle_video,
    summary: "Toggle video status",
    description: "Toggles the video status for the authenticated user in a huddle",
    parameters: [
      huddle_id: [in: :path, description: "Huddle ID", type: :string, required: true]
    ],
    request_body: {"Video toggle request", "application/json", Huddle.VideoToggleRequest},
    responses: [
      ok: {"Video status toggled", "application/json", Common.SuccessResponse},
      bad_request: {"Invalid request", "application/json", Common.ErrorResponse},
      unauthorized: {"Authentication required", "application/json", Common.ErrorResponse}
    ]

  def toggle_video(conn, %{"huddle_id" => huddle_id, "enabled" => enabled}) do
    user_id = conn.assigns[:current_user_id]
    CallService.HuddleManager.toggle_video(huddle_id, user_id, enabled)
    json(conn, %{success: true})
  end
end
