defmodule ExpoController.Orchestration.QueueManager do
  @moduledoc """
  GenServer that manages the build queue and coordinates build assignments.
  Handles queue state and broadcasts events via PubSub.
  """

  use GenServer
  require Logger

  alias ExpoController.Builds
  alias Phoenix.PubSub

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Enqueues a new build.
  """
  def enqueue(build_id) do
    GenServer.call(__MODULE__, {:enqueue, build_id})
  end

  @doc """
  Gets the next available build for a worker.
  """
  def next_for_worker(worker_id) do
    GenServer.call(__MODULE__, {:next_for_worker, worker_id})
  end

  @doc """
  Returns current queue statistics.
  """
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    Logger.info("QueueManager starting...")

    # Restore pending builds from database on startup
    state = restore_queue_from_db()

    # Schedule periodic stats broadcast
    schedule_stats_broadcast()

    Logger.info("QueueManager started with #{length(state.queue)} pending builds")

    {:ok, state}
  end

  @impl true
  def handle_call({:enqueue, build_id}, _from, state) do
    Logger.info("Enqueueing build #{build_id}")

    new_queue = state.queue ++ [build_id]
    new_state = %{state | queue: new_queue}

    broadcast_queue_updated(length(new_queue))

    # Notify idle workers that a job is available
    broadcast_job_available()

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:next_for_worker, worker_id}, _from, state) do
    case state.queue do
      [] ->
        {:reply, {:ok, nil}, state}

      [build_id | rest] ->
        # Try to assign build atomically
        case assign_build_to_worker(build_id, worker_id) do
          {:ok, build} ->
            new_state = %{state | queue: rest}
            broadcast_queue_updated(length(rest))
            {:reply, {:ok, build}, new_state}

          {:error, reason} ->
            # On transient errors (worker busy/offline), keep build in queue
            # On permanent errors (build not found), remove from queue
            case reason do
              r when r in [:worker_busy, :worker_offline, :worker_not_found] ->
                # Keep build in queue for retry
                Logger.warning("Failed to assign build #{build_id} (transient): #{inspect(reason)}")
                {:reply, {:error, reason}, state}

              _ ->
                # Permanent error: mark failed and remove from queue
                Logger.warning("Failed to assign build #{build_id} (permanent): #{inspect(reason)}")
                mark_build_failed(build_id, "Assignment failed: #{inspect(reason)}")
                new_state = %{state | queue: rest}
                {:reply, {:error, reason}, new_state}
            end
        end
    end
  end

  @impl true
  def handle_call(:stats, _from, state) do
    stats = %{
      pending: length(state.queue),
      timestamp: DateTime.utc_now()
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_info(:broadcast_stats, state) do
    stats = %{
      pending_builds: length(state.queue),
      timestamp: DateTime.utc_now()
    }

    broadcast("queue:stats", stats)

    schedule_stats_broadcast()

    {:noreply, state}
  end

  # Private Functions

  defp restore_queue_from_db do
    pending_builds = Builds.list_builds(%{status: :pending})

    queue = Enum.map(pending_builds, & &1.id)

    %{
      queue: queue
    }
  end

  defp assign_build_to_worker(build_id, worker_id) do
    case Builds.get_build(build_id) do
      nil ->
        {:error, :build_not_found}

      build ->
        case Builds.assign_to_worker(build, worker_id) do
          {:ok, assigned_build} ->
            broadcast("build:assigned", %{
              build_id: build_id,
              worker_id: worker_id
            })
            {:ok, assigned_build}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp schedule_stats_broadcast do
    Process.send_after(self(), :broadcast_stats, 5_000) # Every 5 seconds
  end

  defp broadcast_queue_updated(count) do
    broadcast("queue:updated", %{pending_count: count})
  end

  defp broadcast_job_available do
    broadcast("job:available", %{})
  end

  defp mark_build_failed(build_id, error_message) do
    case Builds.get_build(build_id) do
      nil -> :ok
      build ->
        case Builds.fail_build(build.id, error_message) do
          {:ok, _} -> :ok
          {:error, reason} ->
            Logger.error("Failed to mark build #{build_id} as failed: #{inspect(reason)}")
            :ok
        end
    end
  end

  defp broadcast(event, payload) do
    PubSub.broadcast(
      ExpoController.PubSub,
      "builds",
      {event, payload}
    )
  end
end
