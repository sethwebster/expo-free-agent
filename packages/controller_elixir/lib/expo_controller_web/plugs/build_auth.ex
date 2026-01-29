defmodule ExpoControllerWeb.Plugs.BuildAuth do
  @moduledoc """
  Authentication plug for build token access.

  Allows access via either:
  - X-API-Key header (admin access)
  - X-Build-Token header (build submitter access)

  Build token grants access only to the specific build it was issued for.
  """

  import Plug.Conn
  import Phoenix.Controller

  alias ExpoController.Builds

  @behaviour Plug

  @doc """
  Initialize the plug.
  """
  def init(opts), do: opts

  @doc """
  Call the authentication function.
  """
  def call(conn, _opts), do: require_build_or_admin_access(conn)

  @doc """
  Requires either valid API key OR valid build token for the requested build.

  ## Headers
  - X-API-Key: Admin API key (grants access to all builds)
  - X-Build-Token: Build-specific access token (grants access to specific build)

  ## Path params
  - id: Build ID (required)
  """
  defp require_build_or_admin_access(conn) do
    api_key = get_req_header(conn, "x-api-key") |> List.first()
    build_token = get_req_header(conn, "x-build-token") |> List.first()
    build_id = conn.path_params["id"]

    cond do
      # Admin API key
      api_key && valid_api_key?(api_key) ->
        conn

      # Build token
      build_token && build_id ->
        validate_build_token(conn, build_id, build_token)

      true ->
        conn
        |> put_status(:unauthorized)
        |> put_view(json: ExpoControllerWeb.ErrorJSON)
        |> render(:"401", message: "Authentication required. Provide X-API-Key or X-Build-Token header")
        |> halt()
    end
  end

  defp valid_api_key?(provided) do
    expected = Application.get_env(:expo_controller, :api_key)
    Plug.Crypto.secure_compare(provided, expected)
  end

  defp validate_build_token(conn, build_id, build_token) do
    case Builds.get_build(build_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> put_view(json: ExpoControllerWeb.ErrorJSON)
        |> render(:"404", message: "Build not found")
        |> halt()

      build ->
        if build.access_token && Plug.Crypto.secure_compare(build.access_token, build_token) do
          conn |> assign(:build, build)
        else
          conn
          |> put_status(:forbidden)
          |> put_view(json: ExpoControllerWeb.ErrorJSON)
          |> render(:"403", message: "Invalid build token")
          |> halt()
        end
    end
  end
end
