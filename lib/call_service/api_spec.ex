defmodule CallService.ApiSpec do
  @moduledoc """
  OpenAPI specification for the Call Service API.
  """

  alias OpenApiSpex.{Info, OpenApi, Paths, Server, Components, SecurityScheme}
  alias CallService.Router

  @behaviour OpenApi

  @impl OpenApi
  def spec do
    %OpenApi{
      info: %Info{
        title: "Call Service API",
        description: "WebRTC calling and huddle management API",
        version: "1.0.0"
      },
      servers: servers(),
      paths: Paths.from_router(Router),
      components: %Components{
        securitySchemes: %{
          "bearer_auth" => %SecurityScheme{
            type: "http",
            scheme: "bearer",
            bearerFormat: "JWT",
            description: "JWT Bearer token authentication"
          }
        }
      }
    }
    |> OpenApiSpex.resolve_schema_modules()
  end

  defp servers do
    base_url = System.get_env("API_BASE_URL", "/")

    [
      %Server{url: base_url, description: "Call Service API Server"}
    ]
  end
end
