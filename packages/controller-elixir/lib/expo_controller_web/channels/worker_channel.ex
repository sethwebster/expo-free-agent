defmodule ExpoControllerWeb.WorkerChannel do
  @moduledoc """
  Channel for worker communication.
  Workers connect and receive job assignments via push notifications.
  """

  use ExpoControllerWeb, :channel

  require Logger

  alias ExpoController.{Workers, Builds}
  alias ExpoController.Orchestration.QueueManager
  alias Phoenix.PubSub

  @impl true
  def join("worker:" <> worker_id, _payload, socket) do
    if socket.assigns.worker_id == worker_id do
      # Subscribe to build events
      PubSub.subscribe(ExpoController.PubSub, "builds")
      PubSub.subscribe(ExpoController.PubSub, "worker:#{worker_id}")

      # Mark worker as online
      case Workers.get_worker(worker_id) do
        nil ->
          {:error, %{reason: "Worker not found"}}

        worker ->
          Workers.heartbeat_worker(worker)
          Logger.info("Worker #{worker_id} connected via channel")

          # Send current queue stats
          stats = QueueManager.stats()

          {:ok, %{message: "Connected", stats: stats}, socket}
      end
    else
      {:error, %{reason: "Worker ID mismatch"}}
    end
  end

  @impl true
  def handle_in("request_job", _payload, socket) do
    worker_id = socket.assigns.worker_id

    case QueueManager.next_for_worker(worker_id) do
      {:ok, nil} ->
        {:reply, {:ok, %{job: nil}}, socket}

      {:ok, build} ->
        job_payload = %{
          id: build.id,
          platform: build.platform,
          source_url: build_url(build.id, "source"),
          certs_url: certs_url(build),
          submitted_at: DateTime.to_iso8601(build.submitted_at)
        }

        {:reply, {:ok, %{job: job_payload}}, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: inspect(reason)}}, socket}
    end
  end

  @impl true
  def handle_in("heartbeat", %{"build_id" => build_id}, socket) do
    case Builds.record_heartbeat(build_id) do
      {:ok, _build} ->
        {:reply, {:ok, %{success: true}}, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: inspect(reason)}}, socket}
    end
  end

  @impl true
  def handle_in("report_progress", %{"build_id" => build_id, "message" => message}, socket) do
    Builds.add_log(build_id, :info, message)
    {:noreply, socket}
  end

  # Handle broadcasts from QueueManager
  @impl true
  def handle_info({"build:assigned", %{worker_id: worker_id, build_id: build_id}}, socket) do
    if socket.assigns.worker_id == worker_id do
      # Notify worker that a build was assigned to them
      push(socket, "job_assigned", %{build_id: build_id})
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info({"queue:updated", %{pending_count: count}}, socket) do
    # Broadcast queue size updates to all workers
    push(socket, "queue_updated", %{pending_count: count})
    {:noreply, socket}
  end

  @impl true
  def handle_info({"job:available", _payload}, socket) do
    # Notify worker that a job is available
    push(socket, "job_available", %{})
    {:noreply, socket}
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  # Private helpers

  defp build_url(build_id, type) do
    "/api/builds/#{build_id}/download/#{type}"
  end

  defp certs_url(build) do
    if build.certs_path, do: "/api/builds/#{build.id}/certs", else: nil
  end
end
