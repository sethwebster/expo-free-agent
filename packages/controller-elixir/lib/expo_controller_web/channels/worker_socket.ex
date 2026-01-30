defmodule ExpoControllerWeb.WorkerSocket do
  @moduledoc """
  Socket for worker connections via Phoenix Channels.
  Replaces REST polling with WebSocket push notifications.
  """

  use Phoenix.Socket

  ## Channels
  channel "worker:*", ExpoControllerWeb.WorkerChannel

  @impl true
  def connect(%{"api_key" => api_key, "worker_id" => worker_id}, socket, _connect_info) do
    configured_api_key = Application.get_env(:expo_controller, :api_key)

    cond do
      !Plug.Crypto.secure_compare(api_key, configured_api_key) ->
        {:error, :unauthorized}

      !ExpoController.Workers.exists?(worker_id) ->
        {:error, :worker_not_found}

      true ->
        socket = assign(socket, :worker_id, worker_id)
        {:ok, socket}
    end
  end

  @impl true
  def connect(_params, _socket, _connect_info) do
    {:error, :missing_credentials}
  end

  @impl true
  def id(socket), do: "worker_socket:#{socket.assigns.worker_id}"
end
