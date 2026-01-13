defmodule CallService.CallController do
  use Phoenix.Controller, formats: [:json]

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

  def answer(conn, %{"call_id" => call_id, "sdp_answer" => sdp_answer}) do
    user_id = conn.assigns[:current_user_id]
    case CallService.CallManager.answer_call(call_id, user_id, sdp_answer) do
      {:ok, call} -> json(conn, %{success: true, data: call})
      {:error, reason} -> conn |> put_status(400) |> json(%{success: false, error: reason})
    end
  end

  def reject(conn, %{"call_id" => call_id} = params) do
    user_id = conn.assigns[:current_user_id]
    reason = Map.get(params, "reason", "rejected")
    case CallService.CallManager.reject_call(call_id, user_id, reason) do
      {:ok, _} -> json(conn, %{success: true, message: "Call rejected"})
      {:error, reason} -> conn |> put_status(400) |> json(%{success: false, error: reason})
    end
  end

  def end_call(conn, %{"call_id" => call_id}) do
    user_id = conn.assigns[:current_user_id]
    case CallService.CallManager.end_call(call_id, user_id) do
      {:ok, result} -> json(conn, %{success: true, data: result})
      {:error, reason} -> conn |> put_status(400) |> json(%{success: false, error: reason})
    end
  end

  def show(conn, %{"call_id" => call_id}) do
    case CallService.CallManager.get_call(call_id) do
      {:ok, nil} -> conn |> put_status(404) |> json(%{success: false, error: "Call not found"})
      {:ok, call} -> json(conn, %{success: true, data: call})
    end
  end

  def active_calls(conn, _params) do
    user_id = conn.assigns[:current_user_id]
    {:ok, calls} = CallService.CallManager.get_active_calls(user_id)
    json(conn, %{success: true, data: calls})
  end

  def history(conn, params) do
    user_id = conn.assigns[:current_user_id]
    limit = String.to_integer(Map.get(params, "limit", "50"))
    {:ok, calls} = CallService.CallManager.get_call_history(user_id, limit: limit)
    json(conn, %{success: true, data: calls})
  end
end
