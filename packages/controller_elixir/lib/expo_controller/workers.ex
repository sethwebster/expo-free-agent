defmodule ExpoController.Workers do
  @moduledoc """
  The Workers context - handles all worker-related business logic.
  """

  import Ecto.Query, warn: false
  alias ExpoController.Repo
  alias ExpoController.Workers.Worker

  @doc """
  Returns the list of workers.
  """
  def list_workers do
    Repo.all(Worker)
  end

  @doc """
  Gets a single worker.
  Returns nil if the Worker does not exist.
  """
  def get_worker(id), do: Repo.get(Worker, id)

  @doc """
  Gets a single worker, raising if not found.
  """
  def get_worker!(id), do: Repo.get!(Worker, id)

  @doc """
  Registers a new worker.
  """
  def register_worker(attrs \\ %{}) do
    attrs
    |> Worker.registration_changeset()
    |> Repo.insert()
  end

  @doc """
  Updates a worker's heartbeat timestamp.
  """
  def heartbeat_worker(worker) do
    worker
    |> Worker.heartbeat_changeset()
    |> Repo.update()
  end

  @doc """
  Marks a worker as building.
  """
  def mark_building(worker) do
    worker
    |> Worker.building_changeset()
    |> Repo.update()
  end

  @doc """
  Marks a worker as idle.
  """
  def mark_idle(worker) do
    worker
    |> Worker.idle_changeset()
    |> Repo.update()
  end

  @doc """
  Marks a worker as offline.
  """
  def mark_offline(worker) do
    worker
    |> Worker.changeset(%{status: :offline})
    |> Repo.update()
  end

  @doc """
  Marks a worker as offline if not seen recently.
  """
  def mark_offline_if_stale(timeout_seconds \\ 300) do
    cutoff = DateTime.utc_now() |> DateTime.add(-timeout_seconds, :second)

    from(w in Worker,
      where: w.last_seen_at < ^cutoff,
      where: w.status != :offline
    )
    |> Repo.update_all(set: [status: :offline])
  end

  @doc """
  Increments the completed builds counter for a worker.
  """
  def increment_completed(worker) do
    worker
    |> Worker.increment_completed_changeset()
    |> Repo.update()
  end

  @doc """
  Increments the failed builds counter for a worker.
  """
  def increment_failed(worker) do
    worker
    |> Worker.increment_failed_changeset()
    |> Repo.update()
  end

  @doc """
  Returns statistics for all workers.
  """
  def get_statistics do
    query = from w in Worker,
      select: %{
        total: count(w.id),
        idle: fragment("SUM(CASE WHEN ? = 'idle' THEN 1 ELSE 0 END)", w.status),
        building: fragment("SUM(CASE WHEN ? = 'building' THEN 1 ELSE 0 END)", w.status),
        offline: fragment("SUM(CASE WHEN ? = 'offline' THEN 1 ELSE 0 END)", w.status),
        total_completed: sum(w.builds_completed),
        total_failed: sum(w.builds_failed)
      }

    case Repo.one(query) do
      nil -> %{
        total: 0,
        idle: 0,
        building: 0,
        offline: 0,
        total_completed: 0,
        total_failed: 0
      }
      stats -> stats
    end
  end

  @doc """
  Checks if a worker exists.
  """
  def exists?(worker_id) do
    Repo.exists?(from w in Worker, where: w.id == ^worker_id)
  end

  @doc """
  Returns true if the worker owns the given build.
  """
  def owns_build?(worker_id, build_id) do
    Repo.exists?(
      from b in ExpoController.Builds.Build,
        where: b.id == ^build_id and b.worker_id == ^worker_id
    )
  end
end
