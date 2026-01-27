defmodule ExpoController.Builds do
  @moduledoc """
  The Builds context - handles all build-related business logic.
  """

  import Ecto.Query, warn: false
  alias ExpoController.Repo
  alias ExpoController.Builds.{Build, BuildLog}
  alias ExpoController.Workers

  @doc """
  Returns the list of builds with optional filters.
  """
  def list_builds(filters \\ %{}) do
    Build
    |> apply_filters(filters)
    |> order_by([b], desc: b.submitted_at)
    |> Repo.all()
    |> Repo.preload(:worker)
  end

  defp apply_filters(query, filters) do
    Enum.reduce(filters, query, fn
      {:status, status}, query -> where(query, [b], b.status == ^status)
      {:worker_id, worker_id}, query -> where(query, [b], b.worker_id == ^worker_id)
      {:platform, platform}, query -> where(query, [b], b.platform == ^platform)
      _, query -> query
    end)
  end

  @doc """
  Gets a single build.
  """
  def get_build(id) do
    Build
    |> Repo.get(id)
    |> Repo.preload([:worker, :logs])
  end

  @doc """
  Gets a single build, raising if not found.
  """
  def get_build!(id) do
    Build
    |> Repo.get!(id)
    |> Repo.preload([:worker, :logs])
  end

  @doc """
  Creates a build.
  """
  def create_build(attrs \\ %{}) do
    # Generate UUID if not provided
    attrs = Map.put_new(attrs, :id, Ecto.UUID.generate())

    attrs
    |> Build.create_changeset()
    |> Repo.insert()
  end

  @doc """
  Gets the next pending build and locks it for assignment.
  Uses SELECT FOR UPDATE to prevent race conditions.
  """
  def next_pending_for_update do
    from(b in Build,
      where: b.status == :pending,
      order_by: [asc: b.submitted_at],
      limit: 1,
      lock: "FOR UPDATE SKIP LOCKED"
    )
    |> Repo.one()
  end

  @doc """
  Assigns a build to a worker atomically.
  Returns {:ok, build} or {:error, reason}.
  """
  def assign_to_worker(build, worker_id) do
    Repo.transaction(fn ->
      with {:ok, worker} <- get_and_validate_worker(worker_id),
           {:ok, build} <- update_build_assignment(build, worker_id),
           {:ok, _worker} <- Workers.mark_building(worker),
           {:ok, _log} <- add_log(build.id, :info, "Build assigned to worker #{worker.name}") do
        build
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp get_and_validate_worker(worker_id) do
    case Workers.get_worker(worker_id) do
      nil -> {:error, :worker_not_found}
      %{status: :offline} -> {:error, :worker_offline}
      %{status: :building} -> {:error, :worker_busy}
      worker -> {:ok, worker}
    end
  end

  defp update_build_assignment(build, worker_id) do
    build
    |> Build.assign_changeset(worker_id)
    |> Repo.update()
  end

  @doc """
  Records a heartbeat for a build.
  """
  def record_heartbeat(build_id) do
    case get_build(build_id) do
      nil -> {:error, :not_found}
      build ->
        build
        |> Build.heartbeat_changeset()
        |> Repo.update()
    end
  end

  @doc """
  Completes a build successfully.
  """
  def complete_build(build_id, result_path) do
    Repo.transaction(fn ->
      with {:ok, build} <- get_and_validate_build(build_id),
           {:ok, build} <- update_build_complete(build, result_path),
           {:ok, _worker} <- update_worker_on_complete(build.worker_id),
           {:ok, _log} <- add_log(build_id, :info, "Build completed successfully") do
        build
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp get_and_validate_build(build_id) do
    case get_build(build_id) do
      nil -> {:error, :not_found}
      build -> {:ok, build}
    end
  end

  defp update_build_complete(build, result_path) do
    build
    |> Build.complete_changeset(result_path)
    |> Repo.update()
  end

  defp update_worker_on_complete(nil), do: {:ok, nil}
  defp update_worker_on_complete(worker_id) do
    case Workers.get_worker(worker_id) do
      nil -> {:ok, nil}
      worker ->
        with {:ok, worker} <- Workers.increment_completed(worker),
             {:ok, worker} <- Workers.mark_idle(worker) do
          {:ok, worker}
        end
    end
  end

  @doc """
  Fails a build with an error message.
  """
  def fail_build(build_id, error_message) do
    Repo.transaction(fn ->
      with {:ok, build} <- get_and_validate_build(build_id),
           {:ok, build} <- update_build_failed(build, error_message),
           {:ok, _worker} <- update_worker_on_fail(build.worker_id),
           {:ok, _log} <- add_log(build_id, :error, "Build failed: #{error_message}") do
        build
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp update_build_failed(build, error_message) do
    build
    |> Build.fail_changeset(error_message)
    |> Repo.update()
  end

  defp update_worker_on_fail(nil), do: {:ok, nil}
  defp update_worker_on_fail(worker_id) do
    case Workers.get_worker(worker_id) do
      nil -> {:ok, nil}
      worker ->
        with {:ok, worker} <- Workers.increment_failed(worker),
             {:ok, worker} <- Workers.mark_idle(worker) do
          {:ok, worker}
        end
    end
  end

  @doc """
  Cancels a pending or assigned build.
  """
  def cancel_build(build_id) do
    Repo.transaction(fn ->
      with {:ok, build} <- get_and_validate_build(build_id),
           :ok <- validate_cancellable(build),
           {:ok, build} <- update_build_cancelled(build),
           {:ok, _worker} <- release_worker_if_assigned(build.worker_id),
           {:ok, _log} <- add_log(build_id, :info, "Build cancelled") do
        build
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp validate_cancellable(%{status: status}) when status in [:pending, :assigned], do: :ok
  defp validate_cancellable(_), do: {:error, :cannot_cancel}

  defp update_build_cancelled(build) do
    build
    |> Ecto.Changeset.change(status: :cancelled)
    |> Repo.update()
  end

  defp release_worker_if_assigned(nil), do: {:ok, nil}
  defp release_worker_if_assigned(worker_id) do
    case Workers.get_worker(worker_id) do
      nil -> {:ok, nil}
      worker -> Workers.mark_idle(worker)
    end
  end

  @doc """
  Adds a log entry to a build.
  """
  def add_log(build_id, level, message) do
    build_id
    |> BuildLog.create_changeset(level, message)
    |> Repo.insert()
  end

  @doc """
  Gets logs for a build.
  """
  def get_logs(build_id, opts \\ []) do
    limit = Keyword.get(opts, :limit)

    query = from l in BuildLog,
      where: l.build_id == ^build_id,
      order_by: [asc: l.timestamp]

    query = if limit, do: limit(query, ^limit), else: query

    Repo.all(query)
  end

  @doc """
  Finds builds that haven't sent a heartbeat recently and marks them as failed.
  """
  def mark_stuck_builds_as_failed(timeout_seconds \\ 300) do
    cutoff = DateTime.utc_now() |> DateTime.add(-timeout_seconds, :second)

    stuck_builds = from(b in Build,
      where: b.status in [:assigned, :building],
      where: b.last_heartbeat_at < ^cutoff or is_nil(b.last_heartbeat_at)
    )
    |> Repo.all()

    Enum.each(stuck_builds, fn build ->
      fail_build(build.id, "Build timeout - no heartbeat received")
    end)

    length(stuck_builds)
  end

  @doc """
  Returns build statistics.
  """
  def get_statistics do
    query = from b in Build,
      select: %{
        total: count(b.id),
        pending: fragment("SUM(CASE WHEN ? = 'pending' THEN 1 ELSE 0 END)", b.status),
        assigned: fragment("SUM(CASE WHEN ? = 'assigned' THEN 1 ELSE 0 END)", b.status),
        building: fragment("SUM(CASE WHEN ? = 'building' THEN 1 ELSE 0 END)", b.status),
        completed: fragment("SUM(CASE WHEN ? = 'completed' THEN 1 ELSE 0 END)", b.status),
        failed: fragment("SUM(CASE WHEN ? = 'failed' THEN 1 ELSE 0 END)", b.status),
        cancelled: fragment("SUM(CASE WHEN ? = 'cancelled' THEN 1 ELSE 0 END)", b.status)
      }

    case Repo.one(query) do
      nil -> %{
        total: 0,
        pending: 0,
        assigned: 0,
        building: 0,
        completed: 0,
        failed: 0,
        cancelled: 0
      }
      stats -> stats
    end
  end

  @doc """
  Returns the count of pending builds.
  """
  def pending_count do
    Repo.aggregate(
      from(b in Build, where: b.status == :pending),
      :count
    )
  end
end
