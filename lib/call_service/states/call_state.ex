defmodule CallService.States.CallState do
  @moduledoc """
  Formal state machine for call lifecycle using Machinery.

  ## States:
  - `:initiating` - Call being set up
  - `:ringing` - Call is ringing on recipient device(s)
  - `:active` - Call is connected and ongoing
  - `:ended` - Call ended normally
  - `:rejected` - Call was rejected by recipient
  - `:missed` - Call was not answered (timed out)
  - `:failed` - Call failed due to technical issues

  ## Transitions:
  ```
  initiating -> ringing -> active -> ended
       |           |         |
       v           v         v
     failed     rejected   failed
                  |
                  v
               missed
  ```

  ## Usage:

      # Create a new call in initiating state
      call = CallState.new(attrs)

      # Start ringing
      {:ok, call} = CallState.ring(call)

      # Answer the call
      {:ok, call} = CallState.answer(call, user_id)

      # End the call
      {:ok, call} = CallState.end_call(call, user_id)
  """

  use Machinery,
    states: [:initiating, :ringing, :active, :ended, :rejected, :missed, :failed],
    transitions: %{
      initiating: [:ringing, :failed],
      ringing: [:active, :rejected, :missed, :failed],
      active: [:ended, :failed],
      ended: [],
      rejected: [],
      missed: [],
      failed: []
    }

  require Logger

  defstruct [
    :call_id,
    :conversation_id,
    :initiator_id,
    :call_type,
    :state,
    :participants,
    :created_at,
    :ringing_at,
    :answered_at,
    :ended_at,
    :duration_seconds,
    :end_reason,
    :ice_servers,
    :metadata
  ]

  @type participant :: %{
    user_id: String.t(),
    status: atom(),
    joined_at: DateTime.t() | nil,
    left_at: DateTime.t() | nil,
    media: map()
  }

  @type t :: %__MODULE__{
    call_id: String.t(),
    conversation_id: String.t(),
    initiator_id: String.t(),
    call_type: :audio | :video,
    state: atom(),
    participants: [participant()],
    created_at: DateTime.t(),
    ringing_at: DateTime.t() | nil,
    answered_at: DateTime.t() | nil,
    ended_at: DateTime.t() | nil,
    duration_seconds: integer() | nil,
    end_reason: String.t() | nil,
    ice_servers: [map()],
    metadata: map()
  }

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Create a new call in initiating state.
  """
  def new(attrs) do
    initiator = %{
      user_id: attrs[:initiator_id],
      status: :initiating,
      joined_at: DateTime.utc_now(),
      left_at: nil,
      media: %{audio: true, video: attrs[:call_type] == :video}
    }

    recipients = Enum.map(attrs[:participant_ids] || [], fn user_id ->
      %{
        user_id: user_id,
        status: :pending,
        joined_at: nil,
        left_at: nil,
        media: %{audio: false, video: false}
      }
    end)

    %__MODULE__{
      call_id: attrs[:call_id] || generate_id(),
      conversation_id: attrs[:conversation_id],
      initiator_id: attrs[:initiator_id],
      call_type: attrs[:call_type] || :audio,
      state: :initiating,
      participants: [initiator | recipients],
      created_at: DateTime.utc_now(),
      ice_servers: attrs[:ice_servers] || [],
      metadata: attrs[:metadata] || %{}
    }
  end

  @doc """
  Transition call to ringing state.
  """
  def ring(call) do
    case Machinery.transition_to(call, :ringing) do
      {:ok, updated} ->
        participants = Enum.map(updated.participants, fn p ->
          if p.user_id == call.initiator_id do
            %{p | status: :connected}
          else
            %{p | status: :ringing}
          end
        end)
        {:ok, %{updated | ringing_at: DateTime.utc_now(), participants: participants}}
      error ->
        error
    end
  end

  @doc """
  Answer the call (transition to active).
  """
  def answer(call, user_id) do
    case Machinery.transition_to(call, :active) do
      {:ok, updated} ->
        participants = Enum.map(updated.participants, fn p ->
          if p.user_id == user_id do
            %{p | status: :connected, joined_at: DateTime.utc_now()}
          else
            p
          end
        end)
        {:ok, %{updated | answered_at: DateTime.utc_now(), participants: participants}}
      error ->
        error
    end
  end

  @doc """
  Reject the call.
  """
  def reject(call, user_id, reason \\ "rejected") do
    # Update participant status
    participants = Enum.map(call.participants, fn p ->
      if p.user_id == user_id do
        %{p | status: :rejected, left_at: DateTime.utc_now()}
      else
        p
      end
    end)

    updated = %{call | participants: participants}

    # Check if all non-initiator participants rejected
    all_rejected = updated.participants
      |> Enum.reject(&(&1.user_id == call.initiator_id))
      |> Enum.all?(&(&1.status in [:rejected, :missed]))

    if all_rejected do
      case Machinery.transition_to(updated, :rejected) do
        {:ok, rejected} ->
          {:ok, %{rejected | ended_at: DateTime.utc_now(), end_reason: reason}}
        error ->
          error
      end
    else
      {:ok, updated}
    end
  end

  @doc """
  Mark call as missed (timed out).
  """
  def miss(call) do
    case Machinery.transition_to(call, :missed) do
      {:ok, missed} ->
        participants = Enum.map(missed.participants, fn p ->
          if p.status == :ringing do
            %{p | status: :missed}
          else
            p
          end
        end)
        {:ok, %{missed |
          ended_at: DateTime.utc_now(),
          end_reason: "no_answer",
          participants: participants
        }}
      error ->
        error
    end
  end

  @doc """
  End the call normally.
  """
  def end_call(call, ended_by_user_id) do
    case Machinery.transition_to(call, :ended) do
      {:ok, ended} ->
        duration = if call.answered_at do
          DateTime.diff(DateTime.utc_now(), call.answered_at, :second)
        else
          0
        end

        participants = Enum.map(ended.participants, fn p ->
          if p.status == :connected do
            %{p | left_at: DateTime.utc_now()}
          else
            p
          end
        end)

        {:ok, %{ended |
          ended_at: DateTime.utc_now(),
          duration_seconds: duration,
          end_reason: "completed",
          participants: participants,
          metadata: Map.put(ended.metadata, :ended_by, ended_by_user_id)
        }}
      error ->
        error
    end
  end

  @doc """
  Mark call as failed.
  """
  def fail(call, reason) do
    case Machinery.transition_to(call, :failed) do
      {:ok, failed} ->
        {:ok, %{failed | ended_at: DateTime.utc_now(), end_reason: reason}}
      error ->
        error
    end
  end

  @doc """
  Update participant media state.
  """
  def toggle_media(call, user_id, media_type, enabled) do
    participants = Enum.map(call.participants, fn p ->
      if p.user_id == user_id do
        media = Map.put(p.media, media_type, enabled)
        %{p | media: media}
      else
        p
      end
    end)
    {:ok, %{call | participants: participants}}
  end

  @doc """
  Add a participant to an active call (for group calls).
  """
  def add_participant(call, user_id) do
    if call.state == :active do
      participant = %{
        user_id: user_id,
        status: :connected,
        joined_at: DateTime.utc_now(),
        left_at: nil,
        media: %{audio: true, video: call.call_type == :video}
      }
      {:ok, %{call | participants: [participant | call.participants]}}
    else
      {:error, "Can only add participants to active calls"}
    end
  end

  @doc """
  Remove a participant from the call.
  """
  def remove_participant(call, user_id) do
    participants = Enum.map(call.participants, fn p ->
      if p.user_id == user_id do
        %{p | status: :left, left_at: DateTime.utc_now()}
      else
        p
      end
    end)

    # Check if all participants have left
    active_count = Enum.count(participants, &(&1.status == :connected))

    if active_count <= 1 and call.state == :active do
      end_call(%{call | participants: participants}, user_id)
    else
      {:ok, %{call | participants: participants}}
    end
  end

  @doc """
  Get the current state of the call.
  """
  def state(call), do: call.state

  @doc """
  Check if call is in a terminal state.
  """
  def terminal?(call) do
    call.state in [:ended, :rejected, :missed, :failed]
  end

  @doc """
  Get active participant count.
  """
  def active_participant_count(call) do
    Enum.count(call.participants, &(&1.status == :connected))
  end

  @doc """
  Get call summary.
  """
  def summary(call) do
    %{
      call_id: call.call_id,
      state: call.state,
      call_type: call.call_type,
      initiator_id: call.initiator_id,
      participant_count: length(call.participants),
      active_count: active_participant_count(call),
      duration_seconds: call.duration_seconds,
      created_at: call.created_at,
      ended_at: call.ended_at
    }
  end

  # ============================================================================
  # Machinery Callbacks
  # ============================================================================

  @doc false
  def guard_transition(call, :initiating, :ringing) do
    if length(call.participants) > 1 do
      {:ok, call}
    else
      {:error, "Call must have at least one recipient"}
    end
  end

  def guard_transition(call, :ringing, :active) do
    # At least one recipient must have joined
    has_answerer = Enum.any?(call.participants, fn p ->
      p.user_id != call.initiator_id and p.status == :connected
    end)

    if has_answerer do
      {:ok, call}
    else
      {:error, "No recipient has answered the call"}
    end
  end

  def guard_transition(call, _from, _to) do
    {:ok, call}
  end

  @doc false
  def before_transition(call, _from, to) do
    Logger.debug("[CallState] Transitioning call #{call.call_id} to #{to}")
    call
  end

  @doc false
  def after_transition(call, from, to) do
    Logger.info("[CallState] Call #{call.call_id} transitioned from #{from} to #{to}")

    # Emit telemetry
    :telemetry.execute(
      [:call_service, :call, :state_transition],
      %{count: 1, duration: call.duration_seconds || 0},
      %{from: from, to: to, call_type: call.call_type}
    )

    call
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp generate_id do
    "call_" <> (:crypto.strong_rand_bytes(12) |> Base.encode16(case: :lower))
  end
end
