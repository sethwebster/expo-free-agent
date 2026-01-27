defmodule ExpoControllerWeb.PublicController do
  @moduledoc """
  Public API endpoints that don't require authentication.
  Used by landing page and public dashboards.
  """

  use ExpoControllerWeb, :controller

  alias ExpoController.{Builds, Workers}

  @doc """
  Returns public statistics about the build system.
  No authentication required - safe for public consumption.
  """
  def stats(conn, _params) do
    build_stats = Builds.get_statistics()
    worker_stats = Workers.get_statistics()

    # Calculate additional metrics
    total_processed = build_stats.completed + build_stats.failed
    success_rate = if total_processed > 0 do
      Float.round(build_stats.completed / total_processed * 100, 1)
    else
      0.0
    end

    stats = %{
      builds: %{
        total: build_stats.total,
        pending: build_stats.pending,
        building: build_stats.building,
        completed: build_stats.completed,
        failed: build_stats.failed,
        success_rate: success_rate
      },
      workers: %{
        total: worker_stats.total,
        idle: worker_stats.idle,
        building: worker_stats.building,
        offline: worker_stats.offline,
        utilization: if worker_stats.total > 0 do
          Float.round(worker_stats.building / worker_stats.total * 100, 1)
        else
          0.0
        end
      },
      timestamp: DateTime.utc_now()
    }

    json(conn, stats)
  end
end
