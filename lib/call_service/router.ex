defmodule CallService.Router do
  use Phoenix.Router
  import Phoenix.Controller

  pipeline :api do
    plug :accepts, ["json"]
    plug CallService.Plugs.AuthPlug
  end

  pipeline :public do
    plug :accepts, ["json"]
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
