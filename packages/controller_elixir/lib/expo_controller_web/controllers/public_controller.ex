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
  Format matches the landing page NetworkStats interface.
  """
  def stats(conn, _params) do
    build_stats = Builds.get_statistics()
    worker_stats = Workers.get_statistics()

    # Calculate builds today (placeholder - would need date filtering in real impl)
    builds_today = build_stats.completed + build_stats.failed

    # Format response for landing page
    stats = %{
      nodesOnline: worker_stats.idle + worker_stats.building,
      buildsQueued: build_stats.pending,
      activeBuilds: build_stats.building,
      buildsToday: builds_today,
      totalBuilds: build_stats.total
    }

    json(conn, stats)
  end
end
