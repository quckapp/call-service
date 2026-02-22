defmodule CallService.Schemas.Common do
  @moduledoc """
  Common schemas used across the Call Service API.
  """

  alias OpenApiSpex.Schema

  defmodule SuccessResponse do
    @moduledoc "Generic success response"
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "SuccessResponse",
      description: "A generic success response",
      type: :object,
      properties: %{
        success: %Schema{type: :boolean, description: "Indicates if the operation was successful", example: true},
        message: %Schema{type: :string, description: "Optional success message"}
      },
      required: [:success],
      example: %{
        success: true,
        message: "Operation completed successfully"
      }
    })
  end

  defmodule ErrorResponse do
    @moduledoc "Generic error response"
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "ErrorResponse",
      description: "A generic error response",
      type: :object,
      properties: %{
        success: %Schema{type: :boolean, description: "Indicates if the operation was successful", example: false},
        error: %Schema{type: :string, description: "Error message describing what went wrong"}
      },
      required: [:success, :error],
      example: %{
        success: false,
        error: "Invalid request parameters"
      }
    })
  end

  defmodule HealthResponse do
    @moduledoc "Health check response"
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "HealthResponse",
      description: "Health check response",
      type: :object,
      properties: %{
        status: %Schema{type: :string, description: "Service health status", example: "healthy"},
        service: %Schema{type: :string, description: "Service name", example: "call-service"},
        version: %Schema{type: :string, description: "Service version", example: "1.0.0"}
      },
      required: [:status, :service, :version],
      example: %{
        status: "healthy",
        service: "call-service",
        version: "1.0.0"
      }
    })
  end

  defmodule ReadinessResponse do
    @moduledoc "Readiness check response"
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "ReadinessResponse",
      description: "Readiness check response",
      type: :object,
      properties: %{
        ready: %Schema{type: :boolean, description: "Service readiness status"},
        checks: %Schema{
          type: :object,
          description: "Individual component checks",
          additionalProperties: %Schema{type: :string}
        }
      },
      required: [:ready, :checks],
      example: %{
        ready: true,
        checks: %{
          mongo: "ok",
          redis: "ok"
        }
      }
    })
  end
end
