defmodule ExpoControllerWeb.Plugs.WorkerOrVMAuth do
  @moduledoc """
  Authentication plug that accepts either worker tokens or VM tokens.

  Used for endpoints that can be accessed by both:
  - Workers (using X-Worker-Token) - for downloading source to mount into VMs
  - VMs (using X-VM-Token) - for direct download inside VM

  Tries worker auth first, falls back to VM auth.
  """

  import Plug.Conn
  import Phoenix.Controller

  alias ExpoController.Workers
  alias ExpoController.Builds

  @behaviour Plug

  def init(opts), do: opts

  def call(conn, _opts) do
    # Try worker token first
    worker_token = get_req_header(conn, "x-worker-token") |> List.first()
    vm_token = get_req_header(conn, "x-vm-token") |> List.first()

    cond do
      worker_token -> validate_worker_token(conn, worker_token)
      vm_token -> validate_vm_token(conn, vm_token)
      true -> unauthorized(conn, "Provide X-Worker-Token or X-VM-Token header")
    end
  end

  defp validate_worker_token(conn, token) do
    case Workers.get_worker_by_token(token) do
      nil ->
        unauthorized(conn, "Invalid worker token")

      worker ->
        conn |> assign(:worker, worker)
    end
  end

  defp validate_vm_token(conn, vm_token) do
    build_id = conn.path_params["id"]

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
          is_nil(build.vm_token) ->
            forbidden(conn, "VM token not issued. Authenticate first with OTP.")

          DateTime.compare(now, build.vm_token_expires_at) == :gt ->
            forbidden(conn, "VM token expired")

          !Plug.Crypto.secure_compare(build.vm_token, vm_token) ->
            forbidden(conn, "Invalid VM token")

          true ->
            conn |> assign(:build, build)
        end
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
