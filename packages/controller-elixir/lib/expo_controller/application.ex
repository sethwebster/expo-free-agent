defmodule ExpoController.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
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
