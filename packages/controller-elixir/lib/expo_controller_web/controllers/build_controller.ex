defmodule ExpoControllerWeb.BuildController do
  use ExpoControllerWeb, :controller

  alias ExpoController.Builds
  alias ExpoController.Storage.FileStorage

  # No API key required for build submission - open access
  # Build token required for build-specific operations (user access)
  plug ExpoControllerWeb.Plugs.BuildAuth when action in [:logs, :download, :download_default, :retry, :status]

  # Worker or VM token required for source download (workers download + mount, VMs can download directly)
  plug ExpoControllerWeb.Plugs.WorkerOrVMAuth when action in [:download_source]

  # VM token required for VM-only operations (VM access after OTP auth)
  plug ExpoControllerWeb.Plugs.VMAuth when action in [:download_certs_worker, :download_certs_secure, :stream_logs, :upload_artifact, :heartbeat, :telemetry]

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

      # Add build to queue for assignment
      ExpoController.Orchestration.QueueManager.enqueue(build.id)

      conn
      |> put_status(:created)
      |> json(%{
        id: build.id,
        status: build.status,
        platform: build.platform,
        submitted_at: DateTime.to_iso8601(build.submitted_at),
        access_token: build.access_token
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

    # Return object with metadata for extensibility
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
  GET /api/builds/:id/status
  Get build status (TS compatibility endpoint - subset of show).
  Returns numeric timestamps matching TS controller format.
  """
  def status(conn, %{"build_id" => id}) do
    case Builds.get_build(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Build not found"})

      build ->
        json(conn, %{
          id: build.id,
          status: build.status,
          platform: build.platform,
          worker_id: build.worker_id,
          submitted_at: datetime_to_timestamp(build.submitted_at),
          started_at: nil,  # TODO: Add started_at field to Build schema
          completed_at: nil,  # TODO: Add completed_at field to Build schema
          error_message: build.error_message
        })
    end
  end

  @doc """
  GET /api/builds/:id/logs
  Get build logs.
  """
  def logs(conn, %{"build_id" => id} = params) do
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
  def download(conn, %{"build_id" => id, "type" => type}) do
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
  GET /api/builds/:id/download
  Download build result (TS compatibility - defaults to "result" type).
  """
  def download_default(conn, %{"build_id" => id}) do
    download(conn, %{"build_id" => id, "type" => "result"})
  end

  @doc """
  POST /api/builds/:id/cancel
  Cancel a pending or assigned build.
  """
  def cancel(conn, %{"build_id" => id}) do
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
    base = %{
      id: build.id,
      platform: build.platform,
      status: build.status,
      worker_id: build.worker_id,
      worker_name: build.worker && build.worker.name,
      submitted_at: DateTime.to_iso8601(build.submitted_at),
      createdAt: DateTime.to_iso8601(build.submitted_at),
      updated_at: DateTime.to_iso8601(build.updated_at),
      error_message: build.error_message,
      has_result: !is_nil(build.result_path)
    }

    # Only include completedAt if we have the field (omit rather than null)
    # TODO: Add completed_at timestamp field to Build schema
    base
  end

  defp serialize_log(log) do
    %{
      level: log.level,
      message: log.message,
      timestamp: DateTime.to_iso8601(log.timestamp)
    }
  end

  defp datetime_to_timestamp(nil), do: nil
  defp datetime_to_timestamp(%DateTime{} = dt) do
    DateTime.to_unix(dt, :millisecond)
  end

  @doc """
  POST /api/builds/:id/retry
  Retry a build by copying source and certs to new build.
  """
  def retry(conn, %{"build_id" => id}) do
    case Builds.retry_build(id) do
      {:ok, new_build} ->
        json(conn, %{
          id: new_build.id,
          status: new_build.status,
          submitted_at: DateTime.to_iso8601(new_build.submitted_at),
          access_token: new_build.access_token,
          original_build_id: id
        })

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Build not found"})

      {:error, :source_not_found} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Original build source no longer available. Please submit a new build."})

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Retry failed", reason: inspect(reason)})
    end
  end

  @doc """
  GET /api/builds/active
  List active builds (assigned or building).
  """
  def active(conn, _params) do
    builds = Builds.list_active_builds()

    json(conn, %{
      builds: Enum.map(builds, fn b ->
        %{
          id: b.id,
          status: b.status,
          platform: b.platform,
          worker_id: b.worker_id,
          started_at: b.submitted_at && DateTime.to_iso8601(b.submitted_at)
        }
      end)
    })
  end

  ## Worker-authenticated endpoints

  @doc """
  POST /api/builds/:id/logs
  Stream build logs from worker (single or batch mode).
  Requires X-Worker-Id header matching assigned worker.
  """
  def stream_logs(conn, %{"id" => build_id} = params) do
    cond do
      # Batch mode: {"logs": [{"level": "info", "message": "text"}, ...]}
      Map.has_key?(params, "logs") && is_list(params["logs"]) ->
        logs = params["logs"]
        |> Enum.filter(fn log ->
          Map.has_key?(log, "level") && Map.has_key?(log, "message") &&
            log["level"] in ["info", "warn", "error"]
        end)
        |> Enum.map(fn log ->
          %{level: String.to_atom(log["level"]), message: log["message"]}
        end)

        case Builds.add_logs(build_id, logs) do
          {:ok, count} ->
            json(conn, %{success: true, count: count})

          {:error, _reason} ->
            conn
            |> put_status(:internal_server_error)
            |> json(%{error: "Failed to add logs"})
        end

      # Single mode: {"level": "info", "message": "text"}
      Map.has_key?(params, "level") && Map.has_key?(params, "message") ->
        level = params["level"]

        if level in ["info", "warn", "error"] do
          case Builds.add_log(build_id, String.to_atom(level), params["message"]) do
            {:ok, _log} ->
              json(conn, %{success: true})

            {:error, _reason} ->
              conn
              |> put_status(:internal_server_error)
              |> json(%{error: "Failed to add log"})
          end
        else
          conn
          |> put_status(:bad_request)
          |> json(%{error: "Invalid log level. Must be: info, warn, or error"})
        end

      true ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Invalid body. Expected {level, message} or {logs: [...]}"})
    end
  end

  @doc """
  POST /api/builds/:id/artifact
  Upload build artifact (IPA, APK) from VM.
  Requires X-VM-Token header.
  """
  def upload_artifact(conn, %{"id" => build_id} = params) do
    with {:ok, upload} <- get_upload(params, "artifact"),
         {:ok, path} <- FileStorage.save_result(build_id, upload),
         {:ok, _build} <- Builds.complete_build(build_id, path) do
      json(conn, %{success: true})
    else
      {:error, :no_source} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "No artifact file provided"})

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to save artifact: #{inspect(reason)}"})
    end
  end

  @doc """
  POST /api/builds/:id/authenticate
  VM authenticates with OTP and receives temporary token.
  """
  def authenticate(conn, %{"id" => build_id, "otp" => otp}) do
    case Builds.get_build(build_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Build not found"})

      build ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        cond do
          is_nil(build.otp) ->
            conn
            |> put_status(:unauthorized)
            |> json(%{error: "No OTP configured for this build"})

          build.otp != otp ->
            conn
            |> put_status(:unauthorized)
            |> json(%{error: "Invalid OTP"})

          DateTime.compare(now, build.otp_expires_at) == :gt ->
            conn
            |> put_status(:unauthorized)
            |> json(%{error: "OTP expired"})

          true ->
            # OTP valid - generate VM token
            {:ok, updated_build} = build
            |> ExpoController.Builds.Build.generate_vm_token_changeset()
            |> ExpoController.Repo.update()

            Builds.add_log(build_id, :info, "VM authenticated with OTP")

            json(conn, %{
              vm_token: updated_build.vm_token,
              expires_at: DateTime.to_iso8601(updated_build.vm_token_expires_at)
            })
        end
    end
  end

  def authenticate(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing required parameter: otp"})
  end

  @doc """
  GET /api/builds/:id/source
  Download build source (for workers/VMs).
  Requires VM token in X-VM-Token header.
  """
  def download_source(conn, %{"id" => build_id}) do
    IO.puts("📥 Worker downloading source for build #{build_id}")

    case Builds.get_build(build_id) do
      nil ->
        IO.puts("❌ Build #{build_id} not found")
        conn
        |> put_status(:not_found)
        |> json(%{error: "Build not found"})

      build ->
        IO.puts("✓ Source download started for build #{build_id}")
        download_source_file(conn, build)
    end
  end

  defp download_source_file(conn, build) do
    with {:ok, stream} <- FileStorage.read_stream(build.source_path) do
      conn
      |> put_resp_content_type("application/zip")
      |> put_resp_header("content-disposition", "attachment; filename=\"#{build.id}.zip\"")
      |> send_chunked(200)
      |> stream_file(stream)
    else
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Source file not found"})

      {:error, _reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to read source file"})
    end
  end

  @doc """
  GET /api/builds/:id/certs
  Download build certs (for workers).
  No authentication required - workers get URL from poll response.
  """
  def download_certs_worker(conn, %{"id" => build_id}) do
    case Builds.get_build(build_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Build not found"})

      build ->
        download_certs_file(conn, build)
    end
  end

  defp download_certs_file(conn, build) do
    if is_nil(build.certs_path) do
      conn
      |> put_status(:not_found)
      |> json(%{error: "Certs not found"})
    else
      with {:ok, stream} <- FileStorage.read_stream(build.certs_path) do
        conn
        |> put_resp_content_type("application/zip")
        |> put_resp_header("content-disposition", "attachment; filename=\"#{build.id}-certs.zip\"")
        |> send_chunked(200)
        |> stream_file(stream)
      else
        {:error, :not_found} ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "Certs file not found"})

        {:error, _reason} ->
          conn
          |> put_status(:internal_server_error)
          |> json(%{error: "Failed to read certs file"})
      end
    end
  end

  @doc """
  GET /api/builds/:id/certs-secure
  Get build certs in secure JSON format for VM bootstrap.
  Requires X-Worker-Id and X-Build-Id headers.
  Returns: {p12, p12Password, keychainPassword, provisioningProfiles}
  """
  def download_certs_secure(conn, %{"id" => build_id}) do
    IO.puts("🔐 VM requesting secure certs for build #{build_id}")
    build = conn.assigns.build

    if is_nil(build.certs_path) do
      IO.puts("❌ No certs found for build #{build_id}")
      conn
      |> put_status(:not_found)
      |> json(%{error: "Certs not found"})
    else
      try do
        # Generate random keychain password (24 bytes = 32 chars base64)
        keychain_password = :crypto.strong_rand_bytes(24) |> Base.encode64()

        # Read and unzip certs
        certs_data = read_and_unzip_certs(build.certs_path)

        IO.puts("✓ Secure certs sent for build #{build_id} (#{length(certs_data.profiles)} profiles)")

        json(conn, %{
          p12: Base.encode64(certs_data.p12),
          p12Password: certs_data.password,
          keychainPassword: keychain_password,
          provisioningProfiles: Enum.map(certs_data.profiles, &Base.encode64/1)
        })
      rescue
        error ->
          require Logger
          Logger.error("Failed to process certs: #{inspect(error)}")
          IO.puts("❌ Failed to process certs for build #{build_id}: #{inspect(error)}")

          conn
          |> put_status(:internal_server_error)
          |> json(%{error: "Failed to process certs file"})
      end
    end
  end

  @doc """
  POST /api/builds/:id/heartbeat
  Worker sends heartbeat during build.
  Query: ?worker_id=xyz
  Body: {progress: 45} (optional)
  """
  def heartbeat(conn, %{"id" => build_id} = params) do
    worker_id = Map.get(conn.query_params, "worker_id")

    cond do
      is_nil(worker_id) ->
        IO.puts("❌ Heartbeat for build #{build_id}: missing worker_id")
        conn
        |> put_status(:bad_request)
        |> json(%{error: "worker_id required"})

      true ->
        build = Builds.get_build(build_id)

        cond do
          is_nil(build) ->
            IO.puts("❌ Heartbeat for build #{build_id}: build not found")
            conn
            |> put_status(:not_found)
            |> json(%{error: "Build not found"})

          build.worker_id != worker_id ->
            IO.puts("❌ Heartbeat for build #{build_id}: worker mismatch (expected #{build.worker_id}, got #{worker_id})")
            conn
            |> put_status(:forbidden)
            |> json(%{error: "Build not assigned to this worker"})

          true ->
            # Update heartbeat
            {:ok, _build} = Builds.record_heartbeat(build_id)

            # Optionally log progress
            if Map.has_key?(params, "progress") do
              progress = params["progress"]
              IO.puts("💓 Heartbeat for build #{build_id}: progress #{progress}%")
              Builds.add_log(build_id, :info, "Build progress: #{progress}%")
            else
              IO.puts("💓 Heartbeat for build #{build_id}")
            end

            timestamp = DateTime.utc_now() |> DateTime.to_unix(:millisecond)
            json(conn, %{status: "ok", timestamp: timestamp})
        end
    end
  end

  @doc """
  POST /api/builds/:id/telemetry
  Receive detailed telemetry from VM monitor.
  Requires X-Worker-Id and X-Build-Id headers.
  """
  def telemetry(conn, %{"id" => build_id, "type" => type, "timestamp" => timestamp, "data" => data}) do
    IO.puts("📊 Telemetry for build #{build_id}: type=#{type} timestamp=#{timestamp} data=#{inspect(data)}")

    # Log telemetry event
    log_level = if type == "monitor_started", do: :info, else: :info
    message = format_telemetry_message(type, data)
    Builds.add_log(build_id, log_level, message)

    # Save CPU snapshot if applicable
    if type == "cpu_snapshot" && Map.has_key?(data, "cpu_percent") && Map.has_key?(data, "memory_mb") do
      cpu_percent = parse_float(data["cpu_percent"])
      memory_mb = parse_float(data["memory_mb"])

      IO.puts("  → CPU: #{cpu_percent}%, Memory: #{memory_mb}MB")

      # Validate bounds
      if is_valid_cpu_percent(cpu_percent) && is_valid_memory_mb(memory_mb) do
        save_cpu_snapshot(build_id, cpu_percent, memory_mb)
        IO.puts("  ✓ Snapshot saved")
      else
        IO.puts("  ⚠️  Invalid telemetry data (cpu=#{cpu_percent}, mem=#{memory_mb})")
      end
    end

    # Update heartbeat
    {:ok, _build} = Builds.record_heartbeat(build_id)

    json(conn, %{status: "ok"})
  end

  def telemetry(conn, params) do
    IO.puts("❌ Invalid telemetry data: #{inspect(params)}")
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Invalid telemetry data"})
  end

  # Private helpers for worker endpoints

  defp read_and_unzip_certs(certs_path) do
    # Read zip file (join with storage root)
    storage_root = Application.get_env(:expo_controller, :storage_root, "./storage")
    full_path = Path.join(storage_root, certs_path)
    {:ok, zip_data} = File.read(full_path)

    # Unzip and extract
    {:ok, file_list} = :zip.unzip(zip_data, [:memory])

    # Extract components
    p12 = find_file(file_list, fn {name, _} ->
      String.ends_with?(to_string(name), ".p12")
    end)

    password = find_file(file_list, fn {name, _} ->
      to_string(name) == "password.txt"
    end)

    profiles = file_list
    |> Enum.filter(fn {name, _} ->
      String.ends_with?(to_string(name), ".mobileprovision")
    end)
    |> Enum.map(fn {_, data} -> data end)

    unless p12, do: raise("No P12 certificate found in bundle")

    password_str = if password, do: String.trim(to_string(password)), else: ""

    %{
      p12: p12,
      password: password_str,
      profiles: profiles
    }
  end

  defp find_file(file_list, predicate) do
    case Enum.find(file_list, predicate) do
      {_, data} -> data
      nil -> nil
    end
  end

  defp format_telemetry_message(type, data) do
    case type do
      "cpu_snapshot" ->
        cpu = Map.get(data, "cpu_percent", "?")
        mem = Map.get(data, "memory_mb", "?")
        "VM telemetry: CPU #{cpu}%, Memory #{mem}MB"

      "monitor_started" ->
        "VM monitoring started"

      "heartbeat" ->
        "VM heartbeat"

      _ ->
        "VM telemetry: #{type}"
    end
  end

  defp parse_float(value) when is_number(value), do: value
  defp parse_float(value) when is_binary(value) do
    case Float.parse(value) do
      {num, _} -> num
      :error -> nil
    end
  end
  defp parse_float(_), do: nil

  defp is_valid_cpu_percent(nil), do: false
  defp is_valid_cpu_percent(val) when is_number(val) and val >= 0 and val <= 1000, do: true
  defp is_valid_cpu_percent(_), do: false

  defp is_valid_memory_mb(nil), do: false
  defp is_valid_memory_mb(val) when is_number(val) and val >= 0 and val <= 1_000_000, do: true
  defp is_valid_memory_mb(_), do: false

  defp save_cpu_snapshot(build_id, cpu_percent, memory_mb) do
    case Builds.add_cpu_snapshot(build_id, cpu_percent, memory_mb) do
      {:ok, _snapshot} -> :ok
      {:error, reason} ->
        require Logger
        Logger.error("Failed to save CPU snapshot: #{inspect(reason)}")
        :error
    end
  end
end
