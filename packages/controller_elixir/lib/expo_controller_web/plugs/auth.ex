defmodule ExpoControllerWeb.Plugs.Auth do
  @moduledoc """
  Authentication plugs for API key validation and worker access control.
  """

  import Plug.Conn
  import Phoenix.Controller

  alias ExpoController.{Workers, Builds}

  @doc """
  Validates the API key from the X-API-Key header.
  Uses constant-time comparison to prevent timing attacks.
  """
  def require_api_key(conn, _opts) do
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
  Validates worker access to a resource.
  Requires X-Worker-Id header and optionally validates build ownership.
  """
  def require_worker_access(conn, opts \\ []) do
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

    cond do
      is_nil(build_id) ->
        unauthorized(conn, "Missing build ID")

      !Workers.owns_build?(worker_id, build_id) ->
        forbidden(conn, "Worker not assigned to this build")

      true ->
        conn
        |> assign(:worker_id, worker_id)
        |> assign(:build_id, build_id)
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
end
