defmodule ExpoControllerWeb.Plugs.Auth do
  @moduledoc """
  Authentication plugs for API key validation and worker access control.
  """

  import Plug.Conn
  import Phoenix.Controller

  alias ExpoController.Workers
  alias ExpoController.Builds

  @behaviour Plug

  @doc """
  Initialize the plug with the authentication mode.
  """
  def init(mode), do: mode

  @doc """
  Call the appropriate authentication function based on the mode.
  """
  def call(conn, :require_api_key), do: require_api_key(conn)
  def call(conn, :require_worker_access), do: require_worker_access(conn)
  def call(conn, :require_worker_token), do: require_worker_token(conn)

  @doc """
  Validates the API key from the X-API-Key header.
  Uses constant-time comparison to prevent timing attacks.
  """
  defp require_api_key(conn) do
    api_key = Application.get_env(:expo_controller, :api_key)
    provided_key = get_req_header(conn, "x-api-key") |> List.first()

    if provided_key && Plug.Crypto.secure_compare(provided_key, api_key) do
      conn
    else
      conn
      |> put_status(:forbidden)
      |> put_view(json: ExpoControllerWeb.ErrorJSON)
      |> render(:"403", message: "Invalid API key")
      |> halt()
    end
  end

  @doc """
  Validates worker access token from X-Worker-Token header.
  Verifies that the token matches the stored token for the worker.
  """
  defp require_worker_token(conn) do
    token = get_req_header(conn, "x-worker-token") |> List.first()

    cond do
      is_nil(token) ->
        unauthorized(conn, "Missing X-Worker-Token header")

      true ->
        # Find worker by access token
        case Workers.get_worker_by_token(token) do
          nil ->
            unauthorized(conn, "Invalid worker token")

          worker ->
            conn
            |> assign(:worker, worker)
            |> assign(:worker_id, worker.id)
        end
    end
  end

  @doc """
  Validates worker access to a resource.
  Requires X-Worker-Id header and optionally validates build ownership.
  """
  defp require_worker_access(conn, opts \\ []) do
    require_build_id = Keyword.get(opts, :require_build_id, false)
    worker_id = get_req_header(conn, "x-worker-id") |> List.first()

    cond do
      is_nil(worker_id) ->
        unauthorized(conn, "Missing X-Worker-Id header")

      !Workers.exists?(worker_id) ->
        forbidden(conn, "Worker not found")

      require_build_id ->
        validate_build_access(conn, worker_id)

      true ->
        conn
        |> assign(:worker_id, worker_id)
    end
  end

  defp validate_build_access(conn, worker_id) do
    build_id = get_build_id_from_path(conn)
    build = if build_id, do: Builds.get_build(build_id), else: nil

    cond do
      is_nil(build_id) ->
        unauthorized(conn, "Missing build ID")

      is_nil(build) ->
        not_found(conn, "Build not found")

      build.worker_id != worker_id ->
        forbidden(conn, "Build not assigned to this worker")

      true ->
        conn
        |> assign(:worker_id, worker_id)
        |> assign(:build_id, build_id)
        |> assign(:build, build)
    end
  end

  defp get_build_id_from_path(conn) do
    # Try to get build_id from path params or X-Build-Id header
    case conn.path_params do
      %{"id" => id} -> id
      _ ->
        get_req_header(conn, "x-build-id") |> List.first()
    end
  end

  defp unauthorized(conn, message) do
    conn
    |> put_status(:unauthorized)
    |> put_view(json: ExpoControllerWeb.ErrorJSON)
    |> render(:"401", message: message)
    |> halt()
  end

  defp forbidden(conn, message) do
    conn
    |> put_status(:forbidden)
    |> put_view(json: ExpoControllerWeb.ErrorJSON)
    |> render(:"403", message: message)
    |> halt()
  end

  defp not_found(conn, message) do
    conn
    |> put_status(:not_found)
    |> put_view(json: ExpoControllerWeb.ErrorJSON)
    |> render(:"404", message: message)
    |> halt()
  end
end
