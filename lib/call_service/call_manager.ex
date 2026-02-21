defmodule CallService.CallManager do
  @moduledoc "Manages call lifecycle: initiate, answer, reject, end calls"
  use GenServer
  require Logger

  alias CallService.{Repo, RedisClient}
  alias Phoenix.PubSub

  @call_timeout_ms 60_000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    {:ok, %{}}
  end

  # Public API

  def initiate_call(caller_id, recipient_ids, type, metadata \\ %{}) do
    GenServer.call(__MODULE__, {:initiate, caller_id, recipient_ids, type, metadata})
  end

  def answer_call(call_id, user_id, sdp_answer) do
    GenServer.call(__MODULE__, {:answer, call_id, user_id, sdp_answer})
  end

  def reject_call(call_id, user_id, reason \\ "rejected") do
    GenServer.call(__MODULE__, {:reject, call_id, user_id, reason})
  end

  def end_call(call_id, user_id) do
    GenServer.call(__MODULE__, {:end_call, call_id, user_id})
  end

  def get_call(call_id) do
    case Repo.get_call(call_id) do
      nil -> {:ok, nil}
      call -> {:ok, call}
    end
  end

  def get_active_calls(user_id) do
    case RedisClient.get_user_call(user_id) do
      nil -> {:ok, []}
      call_id ->
        case Repo.get_call(call_id) do
          nil -> {:ok, []}
          call -> {:ok, [call]}
        end
    end
  end

  def get_call_history(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    calls = Repo.get_user_call_history(user_id, limit: limit)
    {:ok, calls}
  end

  # GenServer callbacks

  @impl true
  def handle_call({:initiate, caller_id, recipient_ids, type, metadata}, _from, state) do
    call_id = UUID.uuid4()

    call_data = %{
      "_id" => call_id,
      "caller_id" => caller_id,
      "recipient_ids" => recipient_ids,
      "type" => Atom.to_string(type),
      "status" => "ringing",
      "metadata" => metadata,
      "participants" => [%{"user_id" => caller_id, "joined_at" => DateTime.utc_now()}],
      "created_at" => DateTime.utc_now(),
      "updated_at" => DateTime.utc_now()
    }

    case Repo.create_call(call_data) do
      {:ok, _} ->
        RedisClient.set_user_call(caller_id, call_id)

        Enum.each(recipient_ids, fn recipient_id ->
          broadcast_call_event(recipient_id, :incoming_call, call_data)
        end)

        Process.send_after(self(), {:call_timeout, call_id}, @call_timeout_ms)
        {:reply, {:ok, call_data}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:answer, call_id, user_id, _sdp_answer}, _from, state) do
    case Repo.get_call(call_id) do
      nil ->
        {:reply, {:error, "Call not found"}, state}

      %{"status" => "ringing"} = call ->
        participant = %{"user_id" => user_id, "joined_at" => DateTime.utc_now()}

        Repo.update_call(call_id, %{
          "status" => "active",
          "answered_at" => DateTime.utc_now(),
          "updated_at" => DateTime.utc_now()
        })

        Repo.add_participant(call_id, participant)
        RedisClient.set_user_call(user_id, call_id)

        broadcast_call_event(call["caller_id"], :call_answered, %{
          call_id: call_id,
          user_id: user_id
        })

        updated_call = Repo.get_call(call_id)
        {:reply, {:ok, updated_call}, state}

      _ ->
        {:reply, {:error, "Call is not in ringing state"}, state}
    end
  end

  @impl true
  def handle_call({:reject, call_id, user_id, reason}, _from, state) do
    case Repo.get_call(call_id) do
      nil ->
        {:reply, {:error, "Call not found"}, state}

      %{"status" => "ringing"} = call ->
        Repo.update_call(call_id, %{
          "status" => "rejected",
          "rejected_by" => user_id,
          "reject_reason" => reason,
          "ended_at" => DateTime.utc_now(),
          "updated_at" => DateTime.utc_now()
        })

        RedisClient.clear_user_call(call["caller_id"])

        broadcast_call_event(call["caller_id"], :call_rejected, %{
          call_id: call_id,
          user_id: user_id,
          reason: reason
        })

        {:reply, {:ok, %{call_id: call_id, status: "rejected"}}, state}

      _ ->
        {:reply, {:error, "Call is not in ringing state"}, state}
    end
  end

  @impl true
  def handle_call({:end_call, call_id, user_id}, _from, state) do
    case Repo.get_call(call_id) do
      nil ->
        {:reply, {:error, "Call not found"}, state}

      call ->
        duration =
          case call["answered_at"] do
            nil -> 0
            answered_at -> DateTime.diff(DateTime.utc_now(), answered_at, :second)
          end

        Repo.update_call(call_id, %{
          "status" => "ended",
          "ended_at" => DateTime.utc_now(),
          "ended_by" => user_id,
          "duration" => duration,
          "updated_at" => DateTime.utc_now()
        })

        # Clear active call for all participants
        all_user_ids = [call["caller_id"] | call["recipient_ids"]]
        Enum.each(all_user_ids, &RedisClient.clear_user_call/1)

        Enum.each(all_user_ids, fn uid ->
          broadcast_call_event(uid, :call_ended, %{
            call_id: call_id,
            ended_by: user_id,
            duration: duration
          })
        end)

        {:reply, {:ok, %{call_id: call_id, status: "ended", duration: duration}}, state}
    end
  end

  @impl true
  def handle_info({:call_timeout, call_id}, state) do
    case Repo.get_call(call_id) do
      %{"status" => "ringing"} = call ->
        Repo.update_call(call_id, %{
          "status" => "missed",
          "ended_at" => DateTime.utc_now(),
          "updated_at" => DateTime.utc_now()
        })

        RedisClient.clear_user_call(call["caller_id"])

        broadcast_call_event(call["caller_id"], :call_missed, %{call_id: call_id})

      _ ->
        :ok
    end

    {:noreply, state}
  end

  defp broadcast_call_event(user_id, event, data) do
    PubSub.broadcast(
      CallService.PubSub,
      "call:#{user_id}",
      {event, data}
    )
  end
end
