defmodule ExpoControllerWeb.BuildController do
  use ExpoControllerWeb, :controller

  alias ExpoController.Builds
  alias ExpoController.Storage.FileStorage

  plug ExpoControllerWeb.Plugs.Auth, :require_api_key

  @doc """
  POST /api/builds
  Submit a new build.
  """
  def create(conn, params) do
    with {:ok, platform} <- validate_platform(params["platform"]),
         {:ok, source_upload} <- get_upload(params, "source"),
         {:ok, build} <- create_build_record(platform),
         {:ok, source_path} <- FileStorage.save_source(build.id, source_upload),
         {:ok, build} <- update_build_source_path(build, source_path),
         {:ok, build} <- maybe_save_certs(build, params) do

      Builds.add_log(build.id, :info, "Build submitted")

      conn
      |> put_status(:created)
      |> json(%{
        id: build.id,
        status: build.status,
        platform: build.platform,
        submitted_at: DateTime.to_iso8601(build.submitted_at)
      })
    else
      {:error, :invalid_platform} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Invalid platform. Must be 'ios' or 'android'"})

      {:error, :no_source} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Missing source file"})

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Build creation failed", reason: inspect(reason)})
    end
  end

  @doc """
  GET /api/builds
  List all builds with optional filters.
  """
  def index(conn, params) do
    filters = build_filters(params)
    builds = Builds.list_builds(filters)

    json(conn, %{
      builds: Enum.map(builds, &serialize_build/1),
      total: length(builds)
    })
  end

  @doc """
  GET /api/builds/:id
  Get build details.
  """
  def show(conn, %{"id" => id}) do
    case Builds.get_build(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Build not found"})

      build ->
        json(conn, serialize_build(build))
    end
  end

  @doc """
  GET /api/builds/:id/logs
  Get build logs.
  """
  def logs(conn, %{"id" => id} = params) do
    limit = Map.get(params, "limit", "100") |> String.to_integer()
    logs = Builds.get_logs(id, limit: limit)

    json(conn, %{
      logs: Enum.map(logs, &serialize_log/1)
    })
  end

  @doc """
  GET /api/builds/:id/download/:type
  Download build files (source, result).
  """
  def download(conn, %{"id" => id, "type" => type}) do
    with {:ok, build} <- get_build(id),
         {:ok, file_path} <- get_file_path(build, type),
         {:ok, stream} <- FileStorage.read_stream(file_path) do

      filename = Path.basename(file_path)

      conn
      |> put_resp_content_type("application/octet-stream")
      |> put_resp_header("content-disposition", "attachment; filename=\"#{filename}\"")
      |> send_chunked(200)
      |> stream_file(stream)
    else
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Build or file not found"})

      {:error, :invalid_type} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Invalid file type"})
    end
  end

  @doc """
  POST /api/builds/:id/cancel
  Cancel a pending or assigned build.
  """
  def cancel(conn, %{"id" => id}) do
    case Builds.cancel_build(id) do
      {:ok, build} ->
        json(conn, %{
          success: true,
          status: build.status
        })

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Build not found"})

      {:error, :cannot_cancel} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Build cannot be cancelled in current state"})

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Cancellation failed", reason: inspect(reason)})
    end
  end

  @doc """
  GET /api/builds/statistics
  Get build statistics.
  """
  def statistics(conn, _params) do
    stats = Builds.get_statistics()
    json(conn, stats)
  end

  # Private functions

  defp validate_platform(platform) when platform in ["ios", "android"], do: {:ok, String.to_atom(platform)}
  defp validate_platform(_), do: {:error, :invalid_platform}

  defp get_upload(params, field) do
    case Map.get(params, field) do
      %Plug.Upload{} = upload -> {:ok, upload}
      _ -> {:error, :no_source}
    end
  end

  defp create_build_record(platform) do
    Builds.create_build(%{
      platform: platform
    })
  end

  defp update_build_source_path(build, source_path) do
    build
    |> Ecto.Changeset.change(source_path: source_path)
    |> ExpoController.Repo.update()
  end

  defp maybe_save_certs(build, params) do
    case Map.get(params, "certs") do
      %Plug.Upload{} = upload ->
        case FileStorage.save_certs(build.id, upload) do
          {:ok, certs_path} ->
            build
            |> Ecto.Changeset.change(certs_path: certs_path)
            |> ExpoController.Repo.update()

          error -> error
        end

      _ ->
        {:ok, build}
    end
  end

  defp build_filters(params) do
    %{}
    |> maybe_add_filter(:status, params["status"])
    |> maybe_add_filter(:worker_id, params["worker_id"])
    |> maybe_add_filter(:platform, params["platform"])
  end

  defp maybe_add_filter(filters, _key, nil), do: filters
  defp maybe_add_filter(filters, key, value), do: Map.put(filters, key, value)

  defp get_build(id) do
    case Builds.get_build(id) do
      nil -> {:error, :not_found}
      build -> {:ok, build}
    end
  end

  defp get_file_path(build, "source"), do: {:ok, build.source_path}
  defp get_file_path(build, "result") when not is_nil(build.result_path), do: {:ok, build.result_path}
  defp get_file_path(_build, "result"), do: {:error, :not_found}
  defp get_file_path(_build, _type), do: {:error, :invalid_type}

  defp stream_file(conn, stream) do
    Enum.reduce_while(stream, conn, fn chunk, conn ->
      case Plug.Conn.chunk(conn, chunk) do
        {:ok, conn} -> {:cont, conn}
        {:error, :closed} -> {:halt, conn}
      end
    end)
  end

  defp serialize_build(build) do
    %{
      id: build.id,
      platform: build.platform,
      status: build.status,
      worker_id: build.worker_id,
      worker_name: build.worker && build.worker.name,
      submitted_at: DateTime.to_iso8601(build.submitted_at),
      updated_at: DateTime.to_iso8601(build.updated_at),
      error_message: build.error_message,
      has_result: !is_nil(build.result_path)
    }
  end

  defp serialize_log(log) do
    %{
      level: log.level,
      message: log.message,
      timestamp: DateTime.to_iso8601(log.timestamp)
    }
  end
end
