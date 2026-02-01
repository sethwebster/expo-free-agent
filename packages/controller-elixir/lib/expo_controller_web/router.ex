defmodule ExpoControllerWeb.Router do
  use ExpoControllerWeb, :router
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ExpoControllerWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Public dashboard (no auth required)
  scope "/", ExpoControllerWeb do
    pipe_through :browser

    live "/", DashboardLive
  end

  # Public statistics endpoint (no auth required - for landing page)
  scope "/public", ExpoControllerWeb do
    pipe_through :api

    get "/stats", PublicController, :stats
  end

  # Legacy stats endpoint alias for backwards compatibility
  scope "/api", ExpoControllerWeb do
    pipe_through :api

    get "/stats", PublicController, :stats
    get "/health", HealthController, :index  # Health check at /api/health
  end

  # Health check (no auth required)
  scope "/", ExpoControllerWeb do
    pipe_through :api

    get "/health", HealthController, :index
  end

  scope "/api", ExpoControllerWeb do
    pipe_through :api

    # Worker endpoints
    post "/workers/register", WorkerController, :register
    post "/workers/unregister", WorkerController, :unregister
    get "/workers/poll", WorkerController, :poll
    post "/workers/result", WorkerController, :upload_result
    post "/workers/upload", WorkerController, :upload_result  # TS compatibility alias
    post "/workers/fail", WorkerController, :report_failure
    post "/workers/heartbeat", WorkerController, :heartbeat
    post "/workers/abandon", WorkerController, :abandon
    get "/workers/:id/stats", WorkerController, :stats

    # Build endpoints
    get "/builds/statistics", BuildController, :statistics
    get "/builds/active", BuildController, :active
    post "/builds/submit", BuildController, :create  # TS compatibility alias

    resources "/builds", BuildController, only: [:index, :show, :create] do
      get "/status", BuildController, :status  # TS compatibility endpoint
      get "/logs", BuildController, :logs
      get "/download/:type", BuildController, :download
      get "/download", BuildController, :download_default  # TS compatibility (defaults to result)
      post "/cancel", BuildController, :cancel
      post "/retry", BuildController, :retry
    end

    # VM/Worker-authenticated build endpoints
    scope "/builds/:id" do
      post "/authenticate", BuildController, :authenticate  # OTP auth (no token required)
      post "/logs", BuildController, :stream_logs
      post "/heartbeat", BuildController, :heartbeat
      post "/telemetry", BuildController, :telemetry
      get "/source", BuildController, :download_source
      get "/certs", BuildController, :download_certs_worker
      get "/certs-secure", BuildController, :download_certs_secure
    end
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
