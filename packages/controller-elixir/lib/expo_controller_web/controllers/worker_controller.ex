defmodule ExpoControllerWeb.WorkerController do
  use ExpoControllerWeb, :controller

  alias ExpoController.{Workers, Builds}
  alias ExpoController.Storage.FileStorage

  # Workers self-register without API key
  plug ExpoControllerWeb.Plugs.Auth, :require_api_key when action in [:stats]
  plug ExpoControllerWeb.Plugs.Auth, :require_worker_token when action in [:unregister, :abandon]

  @doc """
  POST /api/workers/register
  Registers a new worker or updates existing worker info.
  Handles re-registration atomically to prevent race conditions.
  """
  def register(conn, params) do
    existing_id = params["id"]
    active_build_count = params["active_build_count"] || 0

    # If worker provides existing ID, try to re-register it
    cond do
      existing_id && Workers.get_worker(existing_id) ->
        # Worker exists - re-register atomically
        worker = Workers.get_worker(existing_id)
        IO.puts("Re-registering existing worker: #{existing_id} (#{active_build_count} active builds)")
        handle_reregistration(conn, worker, params)

      existing_id ->
        # ID provided but doesn't exist - create new worker with provided ID
        IO.puts("Worker ID provided but not found, registering as new: #{existing_id}")
        register_new_worker(conn, params, existing_id)

      true ->
        # No ID provided - generate new ID and create worker
        register_new_worker(conn, params, Nanoid.generate())
    end
  end

  defp handle_reregistration(conn, worker, params) do
    alias ExpoController.Repo
    import Ecto.Query

    # Use transaction to prevent race with poll endpoint
    case Repo.transaction(fn ->
      # Re-fetch with lock to prevent concurrent modifications
      locked_worker = from(w in ExpoController.Workers.Worker,
        where: w.id == ^worker.id,
        lock: "FOR UPDATE"
      )
      |> Repo.one!()

      # Update heartbeat and rotate token (preserves status and assigned builds)
      {:ok, updated_worker} = Workers.heartbeat_worker(locked_worker)

      # Log if worker has active builds during re-registration
      active_count = params["active_build_count"] || 0
      if active_count > 0 do
        IO.puts("Worker #{worker.id} re-registering with #{active_count} in-flight builds")
      end

      updated_worker
    end, timeout: 5_000) do
      {:ok, updated_worker} ->
        json(conn, %{
          id: updated_worker.id,
          access_token: updated_worker.access_token,
          status: "re-registered",
          message: "Worker re-registered successfully"
        })

      {:error, reason} ->
        IO.puts("Re-registration transaction failed: #{inspect(reason)}")
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Re-registration failed", reason: inspect(reason)})
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
          access_token: worker.access_token,
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
  POST /api/workers/unregister
  Unregisters a worker (marks as offline and reassigns active builds).
  Requires X-Worker-Token header (validated by auth plug).
  """
  def unregister(conn, _params) do
    # Worker already authenticated via token plug
    worker = conn.assigns.worker

    # Reassign any active builds back to pending
    {reassigned_count, _} = Builds.reassign_worker_builds(worker.id)
    IO.puts("Reassigned #{reassigned_count} builds from worker #{worker.id}")

    case Workers.mark_offline(worker) do
      {:ok, _worker} ->
        json(conn, %{
          success: true,
          message: "Worker unregistered",
          builds_reassigned: reassigned_count
        })

      {:error, _changeset} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to unregister worker"})
    end
  end

  @doc """
  POST /api/workers/abandon
  Worker abandons a build (requeues it for another worker).
  Requires X-Worker-Token header (validated by auth plug).
  """
  def abandon(conn, %{"build_id" => build_id, "reason" => reason} = params) do
    worker_id = params["worker_id"]

    IO.puts("Worker #{worker_id} abandoning build #{build_id}: #{reason}")

    case Builds.requeue_build(build_id) do
      {:ok, _build} ->
        json(conn, %{
          success: true,
          message: "Build requeued successfully"
        })

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Build not found"})

      {:error, _changeset} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to requeue build"})
    end
  end

  @doc """
  GET /api/workers/poll
  Worker polls for next available build.

  Authentication options (in order of preference):
  1. X-Worker-Token header (secure, rotating token)
  2. X-API-Key header + worker_id param (backward compat, requires admin API key)
  """
  def poll(conn, params) do
    token = get_req_header(conn, "x-worker-token") |> List.first()
    api_key = get_req_header(conn, "x-api-key") |> List.first()
    worker_id = params["worker_id"]
    expected_api_key = Application.get_env(:expo_controller, :api_key)

    # Authenticate and get worker
    worker = cond do
      # Method 1: Token-based auth (preferred, secure)
      token ->
        Workers.get_worker_by_token(token)

      # Method 2: API key + worker_id (backward compat for old workers)
      api_key && worker_id && Plug.Crypto.secure_compare(api_key, expected_api_key) ->
        Workers.get_worker(worker_id)

      # No valid auth provided
      true ->
        nil
    end

    case worker do
      nil ->
        IO.puts("Poll failed: No valid authentication")
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Authentication required: provide X-Worker-Token or (X-API-Key + worker_id)"})

      worker ->
        IO.puts("Poll request for worker: #{worker.id}")

        # Update heartbeat and conditionally rotate token
        {:ok, updated_worker} = Workers.heartbeat_worker(worker)

        # Try to assign next pending build from queue
        case ExpoController.Orchestration.QueueManager.next_for_worker(worker.id) do
          {:ok, build} when not is_nil(build) ->
            json(conn, %{
              job: %{
                id: build.id,
                platform: build.platform,
                source_url: "/api/builds/#{build.id}/source",
                certs_url: if(build.certs_path, do: "/api/builds/#{build.id}/certs", else: nil),
                submitted_at: DateTime.to_iso8601(build.submitted_at),
                otp: build.otp  # VM uses this to authenticate
              },
              access_token: updated_worker.access_token
            })

          {:ok, nil} ->
            # No builds available
            json(conn, %{
              job: nil,
              access_token: updated_worker.access_token
            })

          {:error, _reason} ->
            # Assignment failed (worker busy, offline, etc.)
            json(conn, %{
              job: nil,
              access_token: updated_worker.access_token
            })
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
