defmodule ExpoControllerWeb.Router do
  use ExpoControllerWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", ExpoControllerWeb do
    pipe_through :api

    # Worker endpoints
    post "/workers/register", WorkerController, :register
    get "/workers/poll", WorkerController, :poll
    post "/workers/result", WorkerController, :upload_result
    post "/workers/fail", WorkerController, :report_failure
    post "/workers/heartbeat", WorkerController, :heartbeat

    # Build endpoints
    resources "/builds", BuildController, only: [:index, :show, :create] do
      get "/logs", BuildController, :logs
      get "/download/:type", BuildController, :download
      post "/cancel", BuildController, :cancel
    end

    get "/builds/statistics", BuildController, :statistics
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:expo_controller, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through [:fetch_session, :protect_from_forgery]

      live_dashboard "/dashboard", metrics: ExpoControllerWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
