defmodule CallService.SwaggerController do
  @moduledoc """
  Controller for serving Swagger UI and OpenAPI specification.
  """

  use Phoenix.Controller, formats: [:html, :json]

  @swagger_ui_html """
  <!DOCTYPE html>
  <html lang="en">
  <head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Call Service API - Swagger UI</title>
    <link rel="stylesheet" type="text/css" href="https://unpkg.com/swagger-ui-dist@5.9.0/swagger-ui.css">
    <style>
      html { box-sizing: border-box; overflow: -moz-scrollbars-vertical; overflow-y: scroll; }
      *, *:before, *:after { box-sizing: inherit; }
      body { margin: 0; background: #fafafa; }
      .topbar { display: none; }
    </style>
  </head>
  <body>
    <div id="swagger-ui"></div>
    <script src="https://unpkg.com/swagger-ui-dist@5.9.0/swagger-ui-bundle.js"></script>
    <script src="https://unpkg.com/swagger-ui-dist@5.9.0/swagger-ui-standalone-preset.js"></script>
    <script>
      window.onload = function() {
        const ui = SwaggerUIBundle({
          url: "/api/v1/openapi",
          dom_id: '#swagger-ui',
          deepLinking: true,
          presets: [
            SwaggerUIBundle.presets.apis,
            SwaggerUIStandalonePreset
          ],
          plugins: [
            SwaggerUIBundle.plugins.DownloadUrl
          ],
          layout: "StandaloneLayout",
          persistAuthorization: true
        });
        window.ui = ui;
      };
    </script>
  </body>
  </html>
  """

  @doc """
  Serves the Swagger UI HTML page.
  """
  def index(conn, _params) do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, @swagger_ui_html)
  end

  @doc """
  Returns the OpenAPI specification as JSON.
  """
  def openapi(conn, _params) do
    spec = CallService.ApiSpec.spec()
    json(conn, spec)
  end
end
