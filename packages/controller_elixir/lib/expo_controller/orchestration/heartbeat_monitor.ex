defmodule ExpoController.Orchestration.HeartbeatMonitor do
  @moduledoc """
  GenServer that monitors build heartbeats and marks stuck builds as failed.
  Also monitors worker last_seen_at and marks inactive workers as offline.
  """

  use GenServer
  require Logger

  alias ExpoController.{Builds, Workers}

  @default_check_interval 60_000 # 1 minute
  @default_build_timeout 300 # 5 minutes (in seconds)
  @default_worker_timeout 300 # 5 minutes (in seconds)

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Returns the current monitoring configuration.
  """
  def get_config do
    GenServer.call(__MODULE__, :get_config)
  end

  @doc """
  Updates the monitoring configuration.
  """
  def update_config(config) do
    GenServer.call(__MODULE__, {:update_config, config})
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    Logger.info("HeartbeatMonitor starting...")

    state = %{
      check_interval: Keyword.get(opts, :check_interval, @default_check_interval),
      build_timeout: Keyword.get(opts, :build_timeout, @default_build_timeout),
      worker_timeout: Keyword.get(opts, :worker_timeout, @default_worker_timeout)
    }

    # Schedule first check
    schedule_check(state.check_interval)

    Logger.info("HeartbeatMonitor started (check interval: #{state.check_interval}ms, build timeout: #{state.build_timeout}s)")

    {:ok, state}
  end

  @impl true
  def handle_call(:get_config, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call({:update_config, config}, _from, state) do
    new_state = Map.merge(state, config)
    Logger.info("HeartbeatMonitor config updated: #{inspect(new_state)}")
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_info(:check, state) do
    # Check for stuck builds
    stuck_count = check_stuck_builds(state.build_timeout)

    if stuck_count > 0 do
      Logger.warning("Marked #{stuck_count} builds as failed due to timeout")
    end

    # Check for offline workers
    offline_count = check_offline_workers(state.worker_timeout)

    if offline_count > 0 do
      Logger.info("Marked #{offline_count} workers as offline")
    end

    # Schedule next check
    schedule_check(state.check_interval)

    {:noreply, state}
  end

  # Private Functions

  defp schedule_check(interval) do
    Process.send_after(self(), :check, interval)
  end

  defp check_stuck_builds(timeout_seconds) do
    try do
      Builds.mark_stuck_builds_as_failed(timeout_seconds)
    rescue
      error ->
        Logger.error("Error checking stuck builds: #{inspect(error)}")
        0
    end
  end

  defp check_offline_workers(timeout_seconds) do
    try do
      {count, _} = Workers.mark_offline_if_stale(timeout_seconds)
      count
    rescue
      error ->
        Logger.error("Error checking offline workers: #{inspect(error)}")
        0
    end
  end
end
