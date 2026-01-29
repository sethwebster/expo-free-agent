defmodule ExpoControllerWeb.HealthController do
  @moduledoc """
  Health check endpoint for load balancers and monitoring.
  No authentication required.
  """
  use ExpoControllerWeb, :controller

  alias ExpoController.Builds

  @doc """
  GET /health
  Returns health status, queue stats, and storage info.
  """
  def index(conn, _params) do
    queue_stats = %{
      pending: Builds.pending_count(),
      active: Builds.active_count()
    }

    storage_stats = get_storage_stats()

    json(conn, %{
      status: "ok",
      queue: queue_stats,
      storage: storage_stats
    })
  end

  defp get_storage_stats do
    # Basic storage stats - can be expanded later
    %{}
  end
end
