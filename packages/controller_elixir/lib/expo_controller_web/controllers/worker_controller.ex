defmodule ExpoControllerWeb.WorkerController do
  use ExpoControllerWeb, :controller

  alias ExpoController.{Workers, Builds}
  alias ExpoController.Storage.FileStorage

  plug ExpoControllerWeb.Plugs.Auth, :require_api_key when action in [:register, :stats]

  @doc """
  POST /api/workers/register
  Registers a new worker or updates existing worker info.
  """
  def register(conn, params) do
    existing_id = params["id"]

    # If worker provides existing ID, try to re-register it
    cond do
      existing_id && Workers.get_worker(existing_id) ->
        # Worker exists - update heartbeat and return existing ID
        worker = Workers.get_worker(existing_id)
        IO.puts("Re-registering existing worker: #{existing_id}")
        Workers.heartbeat_worker(worker)

        json(conn, %{
          id: worker.id,
          status: "re-registered",
          message: "Worker re-registered successfully"
        })

      existing_id ->
        # ID provided but doesn't exist - create new worker with provided ID
        IO.puts("Worker ID provided but not found, registering as new: #{existing_id}")
        register_new_worker(conn, params, existing_id)

      true ->
        # No ID provided - generate new ID and create worker
        register_new_worker(conn, params, Nanoid.generate())
    end
  end

  defp register_new_worker(conn, params, worker_id) do
    attrs = %{
      id: worker_id,
      name: params["name"] || "Unnamed Worker",
      capabilities: params["capabilities"] || %{}
    }

    IO.puts("Registering worker with attrs: #{inspect(attrs)}")

    case Workers.register_worker(attrs) do
      {:ok, worker} ->
        IO.puts("Worker registered successfully: #{worker.id}")
        json(conn, %{
          id: worker.id,
          status: "registered",
          message: "Worker registered successfully"
        })

      {:error, changeset} ->
        IO.puts("Worker registration failed: #{inspect(changeset)}")
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Registration failed", details: format_errors(changeset)})
    end
  end

  @doc """
  POST /api/workers/:id/unregister
  Unregisters a worker (marks as offline).
  """
  def unregister(conn, %{"id" => worker_id}) do
    case Workers.get_worker(worker_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Worker not found"})

      worker ->
        case Workers.mark_offline(worker) do
          {:ok, _worker} ->
            json(conn, %{success: true, message: "Worker unregistered"})

          {:error, _changeset} ->
            conn
            |> put_status(:internal_server_error)
            |> json(%{error: "Failed to unregister worker"})
        end
    end
  end

  @doc """
  GET /api/workers/poll
  Worker polls for next available build.
  """
  def poll(conn, params) do
    worker_id = params["worker_id"]
    IO.puts("Poll request for worker_id: #{inspect(worker_id)}")

    cond do
      !worker_id ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "worker_id required"})

      true ->
        case Workers.get_worker(worker_id) do
          nil ->
            IO.puts("Worker not found in database: #{worker_id}")
            conn
            |> put_status(:not_found)
            |> json(%{error: "Worker not found"})

          worker ->
            # Update heartbeat
            Workers.heartbeat_worker(worker)

            # Try to assign next pending build
            case try_assign_build(worker_id) do
              {:ok, build} ->
                json(conn, %{
                  job: %{
                    id: build.id,
                    platform: build.platform,
                    source_url: "/api/builds/#{build.id}/source",
                    certs_url: if(build.certs_path, do: "/api/builds/#{build.id}/certs", else: nil),
                    submitted_at: DateTime.to_iso8601(build.submitted_at)
                  }
                })

              {:error, _reason} ->
                json(conn, %{job: nil})
            end
        end
    end
  end

  @doc """
  POST /api/workers/result
  POST /api/workers/upload (TS compatibility)
  Worker uploads build result or reports failure.

  For success=true: requires 'result' file upload
  For success=false: requires 'error_message' field, no file needed
  """
  def upload_result(conn, %{"build_id" => build_id} = params) do
    success = params["success"] || "true"

    case success do
      "false" ->
        # Handle failure case - no result file needed
        error_message = params["error_message"] || "Build failed"
        case Builds.fail_build(build_id, error_message) do
          {:ok, _build} ->
            json(conn, %{success: true, message: "Build marked as failed"})

          {:error, reason} ->
            conn
            |> put_status(:internal_server_error)
            |> json(%{error: "Failed to update build", reason: inspect(reason)})
        end

      _ ->
        # Handle success case - require result file
        with {:ok, _build} <- get_build(build_id),
             {:ok, upload} <- get_upload(params, "result"),
             {:ok, path} <- FileStorage.save_result(build_id, upload),
             {:ok, _build} <- Builds.complete_build(build_id, path) do
          json(conn, %{success: true, message: "Result uploaded successfully"})
        else
          {:error, :not_found} ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Build not found"})

          {:error, :no_upload} ->
            conn
            |> put_status(:bad_request)
            |> json(%{error: "Missing result file"})

          {:error, reason} ->
            conn
            |> put_status(:internal_server_error)
            |> json(%{error: "Upload failed", reason: inspect(reason)})
        end
    end
  end

  @doc """
  POST /api/workers/fail
  Worker reports build failure.
  """
  def report_failure(conn, %{"build_id" => build_id, "error" => error_message}) do
    case Builds.fail_build(build_id, error_message) do
      {:ok, _build} ->
        json(conn, %{success: true, message: "Build marked as failed"})

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to update build", reason: inspect(reason)})
    end
  end

  @doc """
  POST /api/workers/heartbeat
  Worker sends heartbeat.
  """
  def heartbeat(conn, %{"build_id" => build_id}) do
    case Builds.record_heartbeat(build_id) do
      {:ok, _build} ->
        json(conn, %{success: true})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Build not found"})
    end
  end

  # Private functions

  defp try_assign_build(worker_id) do
    alias ExpoController.Repo

    Repo.transaction(fn ->
      case Builds.next_pending_for_update() do
        nil ->
          Repo.rollback(:no_pending_builds)

        build ->
          case Builds.assign_to_worker(build, worker_id) do
            {:ok, assigned} -> assigned
            {:error, reason} -> Repo.rollback(reason)
          end
      end
    end, timeout: 5_000)
  end

  defp get_build(build_id) do
    case Builds.get_build(build_id) do
      nil -> {:error, :not_found}
      build -> {:ok, build}
    end
  end

  defp get_upload(params, field) do
    case Map.get(params, field) do
      %Plug.Upload{} = upload -> {:ok, upload}
      _ -> {:error, :no_upload}
    end
  end

  defp build_download_url(conn, build_id, type) do
    Routes.build_url(conn, :download, build_id, type)
  end

  defp build_certs_url(build) do
    if build.certs_path, do: "/api/builds/#{build.id}/certs", else: nil
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  @doc """
  GET /api/workers/:id/stats
  Get worker statistics including build counts and uptime.
  """
  def stats(conn, %{"id" => id}) do
    case Workers.get_worker(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Worker not found"})

      worker ->
        total_builds = worker.builds_completed + worker.builds_failed

        # Calculate uptime from inserted_at (registration time)
        uptime_ms = DateTime.diff(DateTime.utc_now(), worker.inserted_at, :millisecond)
        uptime_str = format_uptime(uptime_ms)

        json(conn, %{
          totalBuilds: total_builds,
          successfulBuilds: worker.builds_completed,
          failedBuilds: worker.builds_failed,
          workerName: worker.name,
          status: worker.status,
          uptime: uptime_str
        })
    end
  end

  defp format_uptime(uptime_ms) do
    uptime_seconds = div(uptime_ms, 1000)
    uptime_minutes = div(uptime_seconds, 60)
    uptime_hours = div(uptime_minutes, 60)
    uptime_days = div(uptime_hours, 24)

    cond do
      uptime_days > 0 ->
        "#{uptime_days}d #{rem(uptime_hours, 24)}h"

      uptime_hours > 0 ->
        "#{uptime_hours}h #{rem(uptime_minutes, 60)}m"

      uptime_minutes > 0 ->
        "#{uptime_minutes}m #{rem(uptime_seconds, 60)}s"

      true ->
        "#{uptime_seconds}s"
    end
  end
end
