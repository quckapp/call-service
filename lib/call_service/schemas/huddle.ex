defmodule CallService.Schemas.Huddle do
  @moduledoc """
  Huddle-related schemas for the Call Service API.
  """

  alias OpenApiSpex.Schema

  defmodule HuddleRequest do
    @moduledoc "Request schema for creating a huddle"
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "HuddleRequest",
      description: "Request body for creating a new huddle",
      type: :object,
      properties: %{
        channel_id: %Schema{
          type: :string,
          description: "Channel ID where the huddle is created"
        },
        name: %Schema{
          type: :string,
          description: "Name of the huddle"
        },
        settings: %Schema{
          type: :object,
          description: "Huddle settings",
          properties: %{
            max_participants: %Schema{type: :integer, description: "Maximum number of participants"},
            video_enabled: %Schema{type: :boolean, description: "Whether video is enabled by default"},
            recording_enabled: %Schema{type: :boolean, description: "Whether recording is enabled"}
          },
          additionalProperties: true
        }
      },
      required: [:channel_id, :name],
      example: %{
        channel_id: "channel-123",
        name: "Quick Sync",
        settings: %{
          max_participants: 10,
          video_enabled: true,
          recording_enabled: false
        }
      }
    })
  end

  defmodule JoinHuddleRequest do
    @moduledoc "Request schema for joining a huddle"
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "JoinHuddleRequest",
      description: "Request body for joining a huddle",
      type: :object,
      properties: %{
        metadata: %Schema{
          type: :object,
          description: "User metadata for joining",
          additionalProperties: true
        }
      },
      example: %{
        metadata: %{
          device_type: "desktop",
          browser: "Chrome"
        }
      }
    })
  end

  defmodule MuteRequest do
    @moduledoc "Request schema for mute toggle"
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "MuteRequest",
      description: "Request body for toggling mute status",
      type: :object,
      properties: %{
        muted: %Schema{
          type: :boolean,
          description: "Whether the user should be muted"
        }
      },
      required: [:muted],
      example: %{
        muted: true
      }
    })
  end

  defmodule VideoToggleRequest do
    @moduledoc "Request schema for video toggle"
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "VideoToggleRequest",
      description: "Request body for toggling video status",
      type: :object,
      properties: %{
        enabled: %Schema{
          type: :boolean,
          description: "Whether video should be enabled"
        }
      },
      required: [:enabled],
      example: %{
        enabled: true
      }
    })
  end

  defmodule Participant do
    @moduledoc "Huddle participant schema"
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Participant",
      description: "Huddle participant information",
      type: :object,
      properties: %{
        user_id: %Schema{type: :string, description: "User ID of the participant"},
        joined_at: %Schema{type: :string, format: :"date-time", description: "Timestamp when the user joined"},
        is_muted: %Schema{type: :boolean, description: "Whether the participant is muted"},
        video_enabled: %Schema{type: :boolean, description: "Whether participant's video is enabled"},
        is_host: %Schema{type: :boolean, description: "Whether the participant is the host"}
      },
      required: [:user_id, :joined_at, :is_muted, :video_enabled],
      example: %{
        user_id: "user-123",
        joined_at: "2024-01-15T10:30:00Z",
        is_muted: false,
        video_enabled: true,
        is_host: true
      }
    })
  end

  defmodule Huddle do
    @moduledoc "Huddle data schema"
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Huddle",
      description: "Huddle entity",
      type: :object,
      properties: %{
        id: %Schema{type: :string, description: "Unique huddle identifier"},
        channel_id: %Schema{type: :string, description: "Channel ID where the huddle was created"},
        name: %Schema{type: :string, description: "Name of the huddle"},
        host_id: %Schema{type: :string, description: "User ID of the huddle host"},
        participants: %Schema{
          type: :array,
          items: CallService.Schemas.Huddle.Participant,
          description: "List of participants in the huddle"
        },
        status: %Schema{
          type: :string,
          description: "Current status of the huddle",
          enum: ["active", "ended"]
        },
        settings: %Schema{
          type: :object,
          description: "Huddle settings",
          additionalProperties: true
        },
        created_at: %Schema{
          type: :string,
          format: :"date-time",
          description: "Timestamp when the huddle was created"
        },
        ended_at: %Schema{
          type: :string,
          format: :"date-time",
          description: "Timestamp when the huddle ended",
          nullable: true
        }
      },
      required: [:id, :channel_id, :name, :host_id, :participants, :status, :created_at],
      example: %{
        id: "huddle-123456",
        channel_id: "channel-123",
        name: "Quick Sync",
        host_id: "user-123",
        participants: [
          %{
            user_id: "user-123",
            joined_at: "2024-01-15T10:30:00Z",
            is_muted: false,
            video_enabled: true,
            is_host: true
          },
          %{
            user_id: "user-456",
            joined_at: "2024-01-15T10:31:00Z",
            is_muted: true,
            video_enabled: false,
            is_host: false
          }
        ],
        status: "active",
        settings: %{
          max_participants: 10,
          video_enabled: true
        },
        created_at: "2024-01-15T10:30:00Z",
        ended_at: nil
      }
    })
  end

  defmodule HuddleResponse do
    @moduledoc "Huddle response with success wrapper"
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "HuddleResponse",
      description: "Response containing huddle data",
      type: :object,
      properties: %{
        success: %Schema{type: :boolean, description: "Indicates if the operation was successful"},
        data: CallService.Schemas.Huddle.Huddle
      },
      required: [:success, :data],
      example: %{
        success: true,
        data: %{
          id: "huddle-123456",
          channel_id: "channel-123",
          name: "Quick Sync",
          host_id: "user-123",
          participants: [],
          status: "active",
          settings: %{},
          created_at: "2024-01-15T10:30:00Z"
        }
      }
    })
  end

  defmodule HuddleListResponse do
    @moduledoc "Response containing list of huddles"
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "HuddleListResponse",
      description: "Response containing a list of huddles",
      type: :object,
      properties: %{
        success: %Schema{type: :boolean, description: "Indicates if the operation was successful"},
        data: %Schema{
          type: :array,
          items: CallService.Schemas.Huddle.Huddle,
          description: "List of huddles"
        }
      },
      required: [:success, :data],
      example: %{
        success: true,
        data: [
          %{
            id: "huddle-123456",
            channel_id: "channel-123",
            name: "Quick Sync",
            host_id: "user-123",
            participants: [],
            status: "active",
            settings: %{},
            created_at: "2024-01-15T10:30:00Z"
          }
        ]
      }
    })
  end

  defmodule LeaveHuddleResponse do
    @moduledoc "Response for leaving a huddle"
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "LeaveHuddleResponse",
      description: "Response after leaving a huddle",
      type: :object,
      properties: %{
        success: %Schema{type: :boolean, description: "Indicates if the operation was successful"},
        data: %Schema{
          type: :object,
          properties: %{
            huddle_id: %Schema{type: :string, description: "Huddle ID"},
            participant_count: %Schema{type: :integer, description: "Number of remaining participants"}
          }
        }
      },
      required: [:success, :data],
      example: %{
        success: true,
        data: %{
          huddle_id: "huddle-123456",
          participant_count: 3
        }
      }
    })
  end
end
