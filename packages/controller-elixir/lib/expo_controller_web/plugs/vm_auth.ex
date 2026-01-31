defmodule ExpoControllerWeb.Plugs.VMAuth do
  @moduledoc """
  Authentication plug for VM token access.

  Validates VM tokens issued after OTP authentication.
  VM tokens are time-limited (2 hours) and grant access to:
  - Download source code
  - Download signing certificates
  - Upload build results
  - Send heartbeats
  - Send telemetry
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
  def call(conn, _opts), do: require_vm_token(conn)

  # Requires valid VM token for the requested build.
  #
  # Headers:
  # - X-VM-Token: Time-limited VM access token (issued after OTP auth)
  #
  # Path params:
  # - id: Build ID (required)
  defp require_vm_token(conn) do
    vm_token = get_req_header(conn, "x-vm-token") |> List.first()
    build_id = conn.path_params["id"]

    cond do
      vm_token && build_id ->
        validate_vm_token(conn, build_id, vm_token)

      true ->
        conn
        |> put_status(:unauthorized)
        |> put_view(json: ExpoControllerWeb.ErrorJSON)
        |> render(:"401", message: "Authentication required. Provide X-VM-Token header")
        |> halt()
    end
  end

  defp validate_vm_token(conn, build_id, vm_token) do
    case Builds.get_build(build_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> put_view(json: ExpoControllerWeb.ErrorJSON)
        |> render(:"404", message: "Build not found")
        |> halt()

      build ->
        now = DateTime.utc_now()

        cond do
          # No VM token issued yet
          is_nil(build.vm_token) ->
            conn
            |> put_status(:forbidden)
            |> put_view(json: ExpoControllerWeb.ErrorJSON)
            |> render(:"403", message: "VM token not issued. Authenticate first with OTP.")
            |> halt()

          # VM token expired
          DateTime.compare(now, build.vm_token_expires_at) == :gt ->
            conn
            |> put_status(:forbidden)
            |> put_view(json: ExpoControllerWeb.ErrorJSON)
            |> render(:"403", message: "VM token expired")
            |> halt()

          # Token mismatch
          !Plug.Crypto.secure_compare(build.vm_token, vm_token) ->
            conn
            |> put_status(:forbidden)
            |> put_view(json: ExpoControllerWeb.ErrorJSON)
            |> render(:"403", message: "Invalid VM token")
            |> halt()

          # Valid token
          true ->
            conn |> assign(:build, build)
        end
    end
  end
end
