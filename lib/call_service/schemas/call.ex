defmodule CallService.Schemas.Call do
  @moduledoc """
  Call-related schemas for the Call Service API.
  """

  alias OpenApiSpex.Schema

  defmodule InitiateCallRequest do
    @moduledoc "Request schema for initiating a call"
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "InitiateCallRequest",
      description: "Request body for initiating a new call",
      type: :object,
      properties: %{
        recipient_ids: %Schema{
          type: :array,
          items: %Schema{type: :string},
          description: "List of recipient user IDs",
          minItems: 1
        },
        type: %Schema{
          type: :string,
          description: "Type of call",
          enum: ["audio", "video"]
        },
        metadata: %Schema{
          type: :object,
          description: "Additional metadata for the call",
          additionalProperties: true
        }
      },
      required: [:recipient_ids, :type],
      example: %{
        recipient_ids: ["user-456", "user-789"],
        type: "video",
        metadata: %{
          channel_id: "channel-123",
          workspace_id: "workspace-abc"
        }
      }
    })
  end

  defmodule AnswerCallRequest do
    @moduledoc "Request schema for answering a call"
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "AnswerCallRequest",
      description: "Request body for answering an incoming call",
      type: :object,
      properties: %{
        sdp_answer: %Schema{
          type: :string,
          description: "SDP answer for WebRTC connection"
        }
      },
      required: [:sdp_answer],
      example: %{
        sdp_answer: "v=0\r\no=- 123456 2 IN IP4 127.0.0.1\r\n..."
      }
    })
  end

  defmodule RejectCallRequest do
    @moduledoc "Request schema for rejecting a call"
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "RejectCallRequest",
      description: "Request body for rejecting an incoming call",
      type: :object,
      properties: %{
        reason: %Schema{
          type: :string,
          description: "Reason for rejecting the call",
          example: "busy"
        }
      },
      example: %{
        reason: "busy"
      }
    })
  end

  defmodule Call do
    @moduledoc "Call data schema"
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Call",
      description: "Call entity",
      type: :object,
      properties: %{
        id: %Schema{type: :string, description: "Unique call identifier"},
        caller_id: %Schema{type: :string, description: "User ID of the caller"},
        recipient_ids: %Schema{
          type: :array,
          items: %Schema{type: :string},
          description: "List of recipient user IDs"
        },
        type: %Schema{
          type: :string,
          description: "Type of call",
          enum: ["audio", "video"]
        },
        status: %Schema{
          type: :string,
          description: "Current status of the call",
          enum: ["ringing", "answered", "rejected", "ended", "missed", "busy"]
        },
        metadata: %Schema{
          type: :object,
          description: "Additional metadata for the call",
          additionalProperties: true
        },
        started_at: %Schema{
          type: :string,
          format: :"date-time",
          description: "Timestamp when the call was initiated"
        },
        answered_at: %Schema{
          type: :string,
          format: :"date-time",
          description: "Timestamp when the call was answered",
          nullable: true
        },
        ended_at: %Schema{
          type: :string,
          format: :"date-time",
          description: "Timestamp when the call ended",
          nullable: true
        },
        duration: %Schema{
          type: :integer,
          description: "Call duration in seconds",
          nullable: true
        }
      },
      required: [:id, :caller_id, :recipient_ids, :type, :status, :started_at],
      example: %{
        id: "call-123456",
        caller_id: "user-123",
        recipient_ids: ["user-456", "user-789"],
        type: "video",
        status: "answered",
        metadata: %{
          channel_id: "channel-123",
          workspace_id: "workspace-abc"
        },
        started_at: "2024-01-15T10:30:00Z",
        answered_at: "2024-01-15T10:30:05Z",
        ended_at: nil,
        duration: nil
      }
    })
  end

  defmodule CallResponse do
    @moduledoc "Call response with success wrapper"
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "CallResponse",
      description: "Response containing call data",
      type: :object,
      properties: %{
        success: %Schema{type: :boolean, description: "Indicates if the operation was successful"},
        data: CallService.Schemas.Call.Call
      },
      required: [:success, :data],
      example: %{
        success: true,
        data: %{
          id: "call-123456",
          caller_id: "user-123",
          recipient_ids: ["user-456"],
          type: "video",
          status: "ringing",
          metadata: %{},
          started_at: "2024-01-15T10:30:00Z"
        }
      }
    })
  end

  defmodule CallListResponse do
    @moduledoc "Response containing list of calls"
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "CallListResponse",
      description: "Response containing a list of calls",
      type: :object,
      properties: %{
        success: %Schema{type: :boolean, description: "Indicates if the operation was successful"},
        data: %Schema{
          type: :array,
          items: CallService.Schemas.Call.Call,
          description: "List of calls"
        }
      },
      required: [:success, :data],
      example: %{
        success: true,
        data: [
          %{
            id: "call-123456",
            caller_id: "user-123",
            recipient_ids: ["user-456"],
            type: "video",
            status: "ended",
            metadata: %{},
            started_at: "2024-01-15T10:30:00Z",
            ended_at: "2024-01-15T10:35:00Z",
            duration: 300
          }
        ]
      }
    })
  end

  defmodule EndCallResponse do
    @moduledoc "Response for ending a call"
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "EndCallResponse",
      description: "Response after ending a call",
      type: :object,
      properties: %{
        success: %Schema{type: :boolean, description: "Indicates if the operation was successful"},
        data: %Schema{
          type: :object,
          properties: %{
            id: %Schema{type: :string, description: "Call ID"},
            duration: %Schema{type: :integer, description: "Call duration in seconds"},
            ended_at: %Schema{type: :string, format: :"date-time", description: "Timestamp when the call ended"}
          }
        }
      },
      required: [:success, :data],
      example: %{
        success: true,
        data: %{
          id: "call-123456",
          duration: 300,
          ended_at: "2024-01-15T10:35:00Z"
        }
      }
    })
  end
end
