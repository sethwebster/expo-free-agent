defmodule ExpoController.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Validate API key before starting
    api_key = Application.get_env(:expo_controller, :api_key)
    unless api_key && byte_size(api_key) >= 32 do
      raise "CONTROLLER_API_KEY must be set and at least 32 characters"
    end

    children = [
      ExpoControllerWeb.Telemetry,
      ExpoController.Repo,
      {DNSCluster, query: Application.get_env(:expo_controller, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: ExpoController.PubSub},
      # Orchestration GenServers
      {ExpoController.Orchestration.QueueManager, []},
      {ExpoController.Orchestration.HeartbeatMonitor, []},
      # Start to serve requests, typically the last entry
      ExpoControllerWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ExpoController.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ExpoControllerWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
