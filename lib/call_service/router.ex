defmodule CallService.Router do
  use Phoenix.Router
  import Phoenix.Controller

  pipeline :api do
    plug :accepts, ["json"]
    plug CallService.Plugs.AuthPlug
    plug OpenApiSpex.Plug.PutApiSpec, module: CallService.ApiSpec
  end

  pipeline :public do
    plug :accepts, ["json"]
  end

  pipeline :browser do
    plug :accepts, ["html"]
  end

  # Swagger UI routes
  scope "/", CallService do
    pipe_through :browser
    get "/swagger", SwaggerController, :index
  end

  scope "/api", CallService do
    pipe_through :public
    get "/openapi", SwaggerController, :openapi
  end

  scope "/api/v1/calls", CallService do
    pipe_through :api

    post "/initiate", CallController, :initiate
    post "/:call_id/answer", CallController, :answer
    post "/:call_id/reject", CallController, :reject
    post "/:call_id/end", CallController, :end_call
    get "/:call_id", CallController, :show
    get "/user/active", CallController, :active_calls
    get "/user/history", CallController, :history
  end

  scope "/api/v1/huddles", CallService do
    pipe_through :api

    post "/", HuddleController, :create
    post "/:huddle_id/join", HuddleController, :join
    post "/:huddle_id/leave", HuddleController, :leave
    post "/:huddle_id/end", HuddleController, :end_huddle
    get "/:huddle_id", HuddleController, :show
    get "/channel/:channel_id", HuddleController, :channel_huddles
    post "/:huddle_id/mute", HuddleController, :toggle_mute
    post "/:huddle_id/video", HuddleController, :toggle_video
  end

  scope "/health", CallService do
    pipe_through :public
    get "/", HealthController, :index
    get "/ready", HealthController, :ready
  end
end
