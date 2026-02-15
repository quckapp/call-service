defmodule CallService.CallController do
  use Phoenix.Controller, formats: [:json]
  use OpenApiSpex.ControllerSpecs

  alias CallService.Schemas.Call
  alias CallService.Schemas.Common

  tags ["Calls"]
  security [%{"bearer_auth" => []}]

  operation :initiate,
    summary: "Initiate a call",
    description: "Initiates a new call to one or more recipients",
    request_body: {"Call initiation request", "application/json", Call.InitiateCallRequest},
    responses: [
      ok: {"Call initiated successfully", "application/json", Call.CallResponse},
      bad_request: {"Invalid request", "application/json", Common.ErrorResponse},
      unauthorized: {"Authentication required", "application/json", Common.ErrorResponse}
    ]

  def initiate(conn, %{"recipient_ids" => recipient_ids, "type" => type} = params) do
    user_id = conn.assigns[:current_user_id]
    metadata = Map.get(params, "metadata", %{})
    type_atom = String.to_existing_atom(type)

    case CallService.CallManager.initiate_call(user_id, recipient_ids, type_atom, metadata) do
      {:ok, call} -> json(conn, %{success: true, data: call})
      {:error, reason} -> conn |> put_status(400) |> json(%{success: false, error: reason})
    end
  rescue
    ArgumentError -> conn |> put_status(400) |> json(%{success: false, error: "Invalid call type"})
  end

  operation :answer,
    summary: "Answer a call",
    description: "Answers an incoming call with an SDP answer",
    parameters: [
      call_id: [in: :path, description: "Call ID", type: :string, required: true]
    ],
    request_body: {"Answer call request", "application/json", Call.AnswerCallRequest},
    responses: [
      ok: {"Call answered successfully", "application/json", Call.CallResponse},
      bad_request: {"Invalid request or call state", "application/json", Common.ErrorResponse},
      unauthorized: {"Authentication required", "application/json", Common.ErrorResponse}
    ]

  def answer(conn, %{"call_id" => call_id, "sdp_answer" => sdp_answer}) do
    user_id = conn.assigns[:current_user_id]
    case CallService.CallManager.answer_call(call_id, user_id, sdp_answer) do
      {:ok, call} -> json(conn, %{success: true, data: call})
      {:error, reason} -> conn |> put_status(400) |> json(%{success: false, error: reason})
    end
  end

  operation :reject,
    summary: "Reject a call",
    description: "Rejects an incoming call with an optional reason",
    parameters: [
      call_id: [in: :path, description: "Call ID", type: :string, required: true]
    ],
    request_body: {"Reject call request", "application/json", Call.RejectCallRequest},
    responses: [
      ok: {"Call rejected successfully", "application/json", Common.SuccessResponse},
      bad_request: {"Invalid request or call state", "application/json", Common.ErrorResponse},
      unauthorized: {"Authentication required", "application/json", Common.ErrorResponse}
    ]

  def reject(conn, %{"call_id" => call_id} = params) do
    user_id = conn.assigns[:current_user_id]
    reason = Map.get(params, "reason", "rejected")
    case CallService.CallManager.reject_call(call_id, user_id, reason) do
      {:ok, _} -> json(conn, %{success: true, message: "Call rejected"})
      {:error, reason} -> conn |> put_status(400) |> json(%{success: false, error: reason})
    end
  end

  operation :end_call,
    summary: "End a call",
    description: "Ends an active call",
    parameters: [
      call_id: [in: :path, description: "Call ID", type: :string, required: true]
    ],
    responses: [
      ok: {"Call ended successfully", "application/json", Call.EndCallResponse},
      bad_request: {"Invalid request or call state", "application/json", Common.ErrorResponse},
      unauthorized: {"Authentication required", "application/json", Common.ErrorResponse}
    ]

  def end_call(conn, %{"call_id" => call_id}) do
    user_id = conn.assigns[:current_user_id]
    case CallService.CallManager.end_call(call_id, user_id) do
      {:ok, result} -> json(conn, %{success: true, data: result})
      {:error, reason} -> conn |> put_status(400) |> json(%{success: false, error: reason})
    end
  end

  operation :show,
    summary: "Get call details",
    description: "Retrieves details of a specific call",
    parameters: [
      call_id: [in: :path, description: "Call ID", type: :string, required: true]
    ],
    responses: [
      ok: {"Call details", "application/json", Call.CallResponse},
      not_found: {"Call not found", "application/json", Common.ErrorResponse},
      unauthorized: {"Authentication required", "application/json", Common.ErrorResponse}
    ]

  def show(conn, %{"call_id" => call_id}) do
    case CallService.CallManager.get_call(call_id) do
      {:ok, nil} -> conn |> put_status(404) |> json(%{success: false, error: "Call not found"})
      {:ok, call} -> json(conn, %{success: true, data: call})
    end
  end

  operation :active_calls,
    summary: "Get active calls",
    description: "Retrieves all active calls for the authenticated user",
    responses: [
      ok: {"List of active calls", "application/json", Call.CallListResponse},
      unauthorized: {"Authentication required", "application/json", Common.ErrorResponse}
    ]

  def active_calls(conn, _params) do
    user_id = conn.assigns[:current_user_id]
    {:ok, calls} = CallService.CallManager.get_active_calls(user_id)
    json(conn, %{success: true, data: calls})
  end

  operation :history,
    summary: "Get call history",
    description: "Retrieves call history for the authenticated user",
    parameters: [
      limit: [in: :query, description: "Maximum number of calls to return", type: :integer, required: false]
    ],
    responses: [
      ok: {"List of historical calls", "application/json", Call.CallListResponse},
      unauthorized: {"Authentication required", "application/json", Common.ErrorResponse}
    ]

  def history(conn, params) do
    user_id = conn.assigns[:current_user_id]
    limit = String.to_integer(Map.get(params, "limit", "50"))
    {:ok, calls} = CallService.CallManager.get_call_history(user_id, limit: limit)
    json(conn, %{success: true, data: calls})
  end
end
