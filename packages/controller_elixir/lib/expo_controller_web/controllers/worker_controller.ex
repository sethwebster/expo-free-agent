defmodule ExpoControllerWeb.WorkerController do
  use ExpoControllerWeb, :controller

  alias ExpoController.{Workers, Builds}
  alias ExpoController.Storage.FileStorage

  plug ExpoControllerWeb.Plugs.Auth, :require_api_key
  plug ExpoControllerWeb.Plugs.Auth, :require_worker_access when action in [:poll, :upload_result, :heartbeat]

  @doc """
  POST /api/workers/register
  Registers a new worker or updates existing worker info.
  """
  def register(conn, params) do
    attrs = %{
      id: params["id"],
      name: params["name"] || "Unnamed Worker",
      capabilities: params["capabilities"] || %{}
    }

    case Workers.register_worker(attrs) do
      {:ok, worker} ->
        json(conn, %{
          id: worker.id,
          status: "registered",
          message: "Worker registered successfully"
        })

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Registration failed", details: format_errors(changeset)})
    end
  end

  @doc """
  GET /api/workers/poll
  Worker polls for next available build.
  """
  def poll(conn, _params) do
    worker_id = conn.assigns.worker_id

    case Workers.get_worker(worker_id) do
      nil ->
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
                source_url: build_download_url(conn, build.id, "source"),
                certs_url: build_certs_url(build),
                submitted_at: DateTime.to_iso8601(build.submitted_at)
              }
            })

          {:error, _reason} ->
            json(conn, %{job: nil})
        end
    end
  end

  @doc """
  POST /api/workers/result
  Worker uploads build result.
  """
  def upload_result(conn, %{"build_id" => build_id} = params) do
    with {:ok, build} <- get_build(build_id),
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
    case Builds.next_pending_for_update() do
      nil -> {:error, :no_pending_builds}
      build -> Builds.assign_to_worker(build, worker_id)
    end
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
end
