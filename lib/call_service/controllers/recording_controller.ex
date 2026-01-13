defmodule CallService.RecordingController do
  use Phoenix.Controller, formats: [:json]

  alias CallService.{Repo, CallRegistry}

  def start_recording(conn, %{"call_id" => call_id}) do
    user_id = conn.assigns[:user_id]

    case CallRegistry.get_call(call_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Call not found"})
      call ->
        recording_id = UUID.uuid4()

        recording_data = %{
          "_id" => recording_id,
          "call_id" => call_id,
          "channel_id" => call["channel_id"],
          "started_by" => user_id,
          "status" => "recording",
          "started_at" => DateTime.utc_now()
        }

        case Repo.create_recording(recording_data) do
          {:ok, _} ->
            conn
            |> put_status(:created)
            |> json(%{recording_id: recording_id, status: "recording"})
          {:error, reason} ->
            conn
            |> put_status(:internal_server_error)
            |> json(%{error: reason})
        end
    end
  end

  def stop_recording(conn, %{"call_id" => call_id} = params) do
    recording_id = params["recording_id"]

    case Repo.get_recording(recording_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Recording not found"})
      recording ->
        if recording["call_id"] != call_id do
          conn
          |> put_status(:bad_request)
          |> json(%{error: "Recording does not belong to this call"})
        else
          duration = DateTime.diff(DateTime.utc_now(), recording["started_at"], :second)

          Repo.update_recording(recording_id, %{
            "status" => "completed",
            "ended_at" => DateTime.utc_now(),
            "duration" => duration
          })

          json(conn, %{success: true, duration: duration})
        end
    end
  end

  def list_recordings(conn, %{"call_id" => call_id}) do
    recordings = Repo.get_call_recordings(call_id)
    json(conn, %{recordings: recordings})
  end
end
