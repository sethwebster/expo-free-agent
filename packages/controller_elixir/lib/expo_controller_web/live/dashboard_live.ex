defmodule ExpoControllerWeb.DashboardLive do
  @moduledoc """
  LiveView dashboard showing real-time build and worker statistics.
  """

  use ExpoControllerWeb, :live_view

  alias ExpoController.{Builds, Workers}
  alias Phoenix.PubSub

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to real-time updates
      PubSub.subscribe(ExpoController.PubSub, "builds")

      # Schedule periodic refresh
      :timer.send_interval(5000, self(), :refresh_stats)
    end

    socket =
      socket
      |> assign(:build_stats, Builds.get_statistics())
      |> assign(:worker_stats, Workers.get_statistics())
      |> assign(:recent_builds, Builds.list_builds(%{}) |> Enum.take(10))
      |> assign(:workers, Workers.list_workers())
      |> assign(:page_title, "Dashboard")

    {:ok, socket}
  end

  @impl true
  def handle_info(:refresh_stats, socket) do
    socket =
      socket
      |> assign(:build_stats, Builds.get_statistics())
      |> assign(:worker_stats, Workers.get_statistics())

    {:noreply, socket}
  end

  @impl true
  def handle_info({"queue:updated", _payload}, socket) do
    # Refresh build stats when queue updates
    socket = assign(socket, :build_stats, Builds.get_statistics())
    {:noreply, socket}
  end

  @impl true
  def handle_info({"build:assigned", _payload}, socket) do
    # Refresh builds list when assignment happens
    socket =
      socket
      |> assign(:recent_builds, Builds.list_builds(%{}) |> Enum.take(10))
      |> assign(:build_stats, Builds.get_statistics())

    {:noreply, socket}
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-100 p-8">
      <div class="max-w-7xl mx-auto">
        <h1 class="text-4xl font-bold text-gray-900 mb-8">Expo Free Agent Dashboard</h1>

        <!-- Stats Grid -->
        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 mb-8">
          <!-- Build Stats -->
          <div class="bg-white rounded-lg shadow p-6">
            <div class="text-sm font-medium text-gray-500 mb-1">Total Builds</div>
            <div class="text-3xl font-bold text-gray-900"><%= @build_stats.total %></div>
          </div>

          <div class="bg-blue-50 rounded-lg shadow p-6">
            <div class="text-sm font-medium text-blue-600 mb-1">Pending</div>
            <div class="text-3xl font-bold text-blue-700"><%= @build_stats.pending %></div>
          </div>

          <div class="bg-green-50 rounded-lg shadow p-6">
            <div class="text-sm font-medium text-green-600 mb-1">Completed</div>
            <div class="text-3xl font-bold text-green-700"><%= @build_stats.completed %></div>
          </div>

          <div class="bg-red-50 rounded-lg shadow p-6">
            <div class="text-sm font-medium text-red-600 mb-1">Failed</div>
            <div class="text-3xl font-bold text-red-700"><%= @build_stats.failed %></div>
          </div>
        </div>

        <!-- Worker Stats -->
        <div class="bg-white rounded-lg shadow p-6 mb-8">
          <h2 class="text-2xl font-bold text-gray-900 mb-4">Workers</h2>
          <div class="grid grid-cols-1 md:grid-cols-4 gap-4">
            <div>
              <div class="text-sm font-medium text-gray-500">Total Workers</div>
              <div class="text-2xl font-bold text-gray-900"><%= @worker_stats.total %></div>
            </div>
            <div>
              <div class="text-sm font-medium text-green-600">Idle</div>
              <div class="text-2xl font-bold text-green-700"><%= @worker_stats.idle %></div>
            </div>
            <div>
              <div class="text-sm font-medium text-blue-600">Building</div>
              <div class="text-2xl font-bold text-blue-700"><%= @worker_stats.building %></div>
            </div>
            <div>
              <div class="text-sm font-medium text-gray-600">Offline</div>
              <div class="text-2xl font-bold text-gray-700"><%= @worker_stats.offline %></div>
            </div>
          </div>
        </div>

        <!-- Recent Builds -->
        <div class="bg-white rounded-lg shadow overflow-hidden">
          <div class="px-6 py-4 border-b border-gray-200">
            <h2 class="text-2xl font-bold text-gray-900">Recent Builds</h2>
          </div>
          <div class="overflow-x-auto">
            <table class="min-w-full divide-y divide-gray-200">
              <thead class="bg-gray-50">
                <tr>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">ID</th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Platform</th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Status</th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Worker</th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Submitted</th>
                </tr>
              </thead>
              <tbody class="bg-white divide-y divide-gray-200">
                <%= for build <- @recent_builds do %>
                  <tr>
                    <td class="px-6 py-4 whitespace-nowrap text-sm font-mono text-gray-900">
                      <%= String.slice(build.id, 0..7) %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                      <%= build.platform %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap">
                      <span class={"px-2 inline-flex text-xs leading-5 font-semibold rounded-full #{status_color(build.status)}"}>
                        <%= build.status %>
                      </span>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                      <%= if build.worker, do: build.worker.name, else: "-" %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                      <%= relative_time(build.submitted_at) %>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>

        <!-- Workers List -->
        <div class="bg-white rounded-lg shadow overflow-hidden mt-8">
          <div class="px-6 py-4 border-b border-gray-200">
            <h2 class="text-2xl font-bold text-gray-900">Active Workers</h2>
          </div>
          <div class="overflow-x-auto">
            <table class="min-w-full divide-y divide-gray-200">
              <thead class="bg-gray-50">
                <tr>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Name</th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Status</th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Completed</th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Failed</th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Last Seen</th>
                </tr>
              </thead>
              <tbody class="bg-white divide-y divide-gray-200">
                <%= for worker <- @workers do %>
                  <tr>
                    <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                      <%= worker.name %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap">
                      <span class={"px-2 inline-flex text-xs leading-5 font-semibold rounded-full #{worker_status_color(worker.status)}"}>
                        <%= worker.status %>
                      </span>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                      <%= worker.builds_completed %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                      <%= worker.builds_failed %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                      <%= if worker.last_seen_at, do: relative_time(worker.last_seen_at), else: "Never" %>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Helper functions

  defp status_color(:pending), do: "bg-yellow-100 text-yellow-800"
  defp status_color(:assigned), do: "bg-blue-100 text-blue-800"
  defp status_color(:building), do: "bg-indigo-100 text-indigo-800"
  defp status_color(:completed), do: "bg-green-100 text-green-800"
  defp status_color(:failed), do: "bg-red-100 text-red-800"
  defp status_color(:cancelled), do: "bg-gray-100 text-gray-800"
  defp status_color(_), do: "bg-gray-100 text-gray-800"

  defp worker_status_color(:idle), do: "bg-green-100 text-green-800"
  defp worker_status_color(:building), do: "bg-blue-100 text-blue-800"
  defp worker_status_color(:offline), do: "bg-gray-100 text-gray-800"
  defp worker_status_color(_), do: "bg-gray-100 text-gray-800"

  defp relative_time(datetime) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, datetime, :second)

    cond do
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86400)}d ago"
    end
  end
end
