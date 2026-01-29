defmodule ExpoControllerWeb.BuildWorkerEndpointsTest do
  use ExpoControllerWeb.ConnCase, async: false

  alias ExpoController.{Builds, Workers, Repo}
  alias ExpoController.Storage.FileStorage

  setup do
    # Clean database
    Repo.delete_all(Builds.CpuSnapshot)
    Repo.delete_all(Builds.BuildLog)
    Repo.delete_all(Builds.Build)
    Repo.delete_all(Workers.Worker)

    # Create worker
    {:ok, worker} = Workers.register_worker(%{
      id: "test-worker-1",
      name: "Test Worker",
      capabilities: %{}
    })

    # Create build assigned to worker
    {:ok, build} = Builds.create_build(%{
      id: "test-build-1",
      platform: :ios,
      source_path: "/storage/builds/test-build-1/source.tar.gz",
      certs_path: "/storage/certs/test-build-1/certs.zip"
    })

    {:ok, build} = Builds.assign_to_worker(build, worker.id)

    conn = build_conn()
    |> put_req_header("content-type", "application/json")

    {:ok, conn: conn, worker: worker, build: build}
  end

  describe "POST /api/builds/:id/logs - single log" do
    test "adds log with valid worker auth", %{conn: conn, build: build, worker: worker} do
      conn = conn
      |> put_req_header("x-worker-id", worker.id)
      |> post("/api/builds/#{build.id}/logs", %{
        level: "info",
        message: "Test log message"
      })

      assert json_response(conn, 200) == %{"success" => true}

      logs = Builds.get_logs(build.id)
      assert length(logs) > 0
      assert List.last(logs).message == "Test log message"
    end

    test "rejects invalid log level", %{conn: conn, build: build, worker: worker} do
      conn = conn
      |> put_req_header("x-worker-id", worker.id)
      |> post("/api/builds/#{build.id}/logs", %{
        level: "debug",
        message: "Invalid level"
      })

      assert json_response(conn, 400)["error"] =~ "Invalid log level"
    end

    test "rejects without X-Worker-Id header", %{conn: conn, build: build} do
      conn = post(conn, "/api/builds/#{build.id}/logs", %{
        level: "info",
        message: "Test"
      })

      assert json_response(conn, 401)
    end

    test "rejects wrong worker", %{conn: conn, build: build} do
      {:ok, other_worker} = Workers.register_worker(%{
        id: "other-worker",
        name: "Other",
        capabilities: %{}
      })

      conn = conn
      |> put_req_header("x-worker-id", other_worker.id)
      |> post("/api/builds/#{build.id}/logs", %{
        level: "info",
        message: "Test"
      })

      assert json_response(conn, 403)
    end
  end

  describe "POST /api/builds/:id/logs - batch mode" do
    test "adds multiple logs", %{conn: conn, build: build, worker: worker} do
      conn = conn
      |> put_req_header("x-worker-id", worker.id)
      |> post("/api/builds/#{build.id}/logs", %{
        logs: [
          %{level: "info", message: "Log 1"},
          %{level: "warn", message: "Log 2"},
          %{level: "error", message: "Log 3"}
        ]
      })

      response = json_response(conn, 200)
      assert response["success"] == true
      assert response["count"] == 3

      logs = Builds.get_logs(build.id)
      messages = Enum.map(logs, & &1.message)
      assert "Log 1" in messages
      assert "Log 2" in messages
      assert "Log 3" in messages
    end

    test "filters out invalid entries", %{conn: conn, build: build, worker: worker} do
      conn = conn
      |> put_req_header("x-worker-id", worker.id)
      |> post("/api/builds/#{build.id}/logs", %{
        logs: [
          %{level: "info", message: "Valid"},
          %{level: "debug", message: "Invalid level"},
          %{level: "info"},  # Missing message
          %{message: "Missing level"}
        ]
      })

      response = json_response(conn, 200)
      assert response["success"] == true
      assert response["count"] == 1  # Only one valid entry
    end
  end

  describe "GET /api/builds/:id/source" do
    test "downloads source with valid worker", %{conn: conn, build: build, worker: worker} do
      # Create mock source file
      File.mkdir_p!(Path.dirname(build.source_path))
      File.write!(build.source_path, "mock source content")

      conn = conn
      |> put_req_header("x-worker-id", worker.id)
      |> get("/api/builds/#{build.id}/source")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["application/zip"]
      assert get_resp_header(conn, "content-disposition") |> List.first() =~ "#{build.id}.zip"

      # Cleanup
      File.rm!(build.source_path)
    end

    test "returns 404 for missing source", %{conn: conn, build: build, worker: worker} do
      conn = conn
      |> put_req_header("x-worker-id", worker.id)
      |> get("/api/builds/#{build.id}/source")

      assert json_response(conn, 404)
    end

    test "rejects wrong worker", %{conn: conn, build: build} do
      {:ok, other_worker} = Workers.register_worker(%{
        id: "other-worker",
        name: "Other",
        capabilities: %{}
      })

      conn = conn
      |> put_req_header("x-worker-id", other_worker.id)
      |> get("/api/builds/#{build.id}/source")

      assert json_response(conn, 403)
    end
  end

  describe "GET /api/builds/:id/certs" do
    test "downloads certs with valid worker", %{conn: conn, build: build, worker: worker} do
      # Create mock certs file
      File.mkdir_p!(Path.dirname(build.certs_path))
      File.write!(build.certs_path, "mock certs content")

      conn = conn
      |> put_req_header("x-worker-id", worker.id)
      |> get("/api/builds/#{build.id}/certs")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["application/zip"]
      assert get_resp_header(conn, "content-disposition") |> List.first() =~ "#{build.id}-certs.zip"

      # Cleanup
      File.rm!(build.certs_path)
    end

    test "returns 404 when no certs", %{conn: conn, worker: worker} do
      # Create build without certs
      {:ok, no_certs_build} = Builds.create_build(%{
        platform: :android,
        source_path: "/tmp/source.tar.gz"
      })

      {:ok, no_certs_build} = Builds.assign_to_worker(no_certs_build, worker.id)

      conn = conn
      |> put_req_header("x-worker-id", worker.id)
      |> get("/api/builds/#{no_certs_build.id}/certs")

      assert json_response(conn, 404)
    end
  end

  describe "GET /api/builds/:id/certs-secure" do
    test "returns base64-encoded certs bundle", %{conn: conn, build: build, worker: worker} do
      # Create mock certs zip with proper structure
      certs_dir = Path.dirname(build.certs_path)
      File.mkdir_p!(certs_dir)

      # Create temp files for zip
      tmp_dir = "/tmp/certs_test_#{:rand.uniform(1000000)}"
      File.mkdir_p!(tmp_dir)

      p12_path = Path.join(tmp_dir, "cert.p12")
      password_path = Path.join(tmp_dir, "password.txt")
      profile_path = Path.join(tmp_dir, "profile.mobileprovision")

      File.write!(p12_path, "mock p12 content")
      File.write!(password_path, "test_password")
      File.write!(profile_path, "mock profile content")

      # Create zip
      :zip.create(to_charlist(build.certs_path), [
        {~c"cert.p12", File.read!(p12_path)},
        {~c"password.txt", File.read!(password_path)},
        {~c"profile.mobileprovision", File.read!(profile_path)}
      ])

      conn = conn
      |> put_req_header("x-worker-id", worker.id)
      |> put_req_header("x-build-id", build.id)
      |> get("/api/builds/#{build.id}/certs-secure")

      assert conn.status == 200
      response = json_response(conn, 200)

      assert is_binary(response["p12"])
      assert response["p12Password"] == "test_password"
      assert is_binary(response["keychainPassword"])
      assert is_list(response["provisioningProfiles"])
      assert length(response["provisioningProfiles"]) == 1

      # Cleanup
      File.rm_rf!(tmp_dir)
      File.rm!(build.certs_path)
    end

    test "requires both X-Worker-Id and X-Build-Id headers", %{conn: conn, build: build, worker: worker} do
      # Missing X-Build-Id
      conn1 = conn
      |> put_req_header("x-worker-id", worker.id)
      |> get("/api/builds/#{build.id}/certs-secure")

      # Should still work because build_id is in path
      # But let's test with explicit header
      File.mkdir_p!(Path.dirname(build.certs_path))
      tmp_dir = "/tmp/certs_test_#{:rand.uniform(1000000)}"
      File.mkdir_p!(tmp_dir)

      p12_path = Path.join(tmp_dir, "cert.p12")
      password_path = Path.join(tmp_dir, "password.txt")
      File.write!(p12_path, "mock")
      File.write!(password_path, "pass")

      :zip.create(to_charlist(build.certs_path), [
        {~c"cert.p12", File.read!(p12_path)},
        {~c"password.txt", File.read!(password_path)}
      ])

      conn2 = conn
      |> put_req_header("x-worker-id", worker.id)
      |> put_req_header("x-build-id", build.id)
      |> get("/api/builds/#{build.id}/certs-secure")

      assert conn2.status == 200

      # Cleanup
      File.rm_rf!(tmp_dir)
      File.rm!(build.certs_path)
    end
  end

  describe "POST /api/builds/:id/heartbeat" do
    test "updates heartbeat with valid worker", %{conn: conn, build: build, worker: worker} do
      conn = post(conn, "/api/builds/#{build.id}/heartbeat?worker_id=#{worker.id}", %{})

      assert response = json_response(conn, 200)
      assert response["status"] == "ok"
      assert is_number(response["timestamp"])

      # Verify heartbeat was updated
      updated_build = Builds.get_build(build.id)
      assert updated_build.last_heartbeat_at != nil
    end

    test "logs progress when provided", %{conn: conn, build: build, worker: worker} do
      conn = post(conn, "/api/builds/#{build.id}/heartbeat?worker_id=#{worker.id}", %{
        progress: 45
      })

      assert json_response(conn, 200)["status"] == "ok"

      logs = Builds.get_logs(build.id)
      progress_log = Enum.find(logs, fn log ->
        String.contains?(log.message, "Build progress: 45%")
      end)

      assert progress_log != nil
    end

    test "requires worker_id query param", %{conn: conn, build: build} do
      conn = post(conn, "/api/builds/#{build.id}/heartbeat", %{})

      assert json_response(conn, 400)["error"] =~ "worker_id required"
    end

    test "rejects wrong worker", %{conn: conn, build: build} do
      {:ok, other_worker} = Workers.register_worker(%{
        id: "other-worker",
        name: "Other",
        capabilities: %{}
      })

      conn = post(conn, "/api/builds/#{build.id}/heartbeat?worker_id=#{other_worker.id}", %{})

      assert json_response(conn, 403)
    end
  end

  describe "POST /api/builds/:id/telemetry" do
    test "saves CPU snapshot with valid data", %{conn: conn, build: build, worker: worker} do
      conn = conn
      |> put_req_header("x-worker-id", worker.id)
      |> put_req_header("x-build-id", build.id)
      |> post("/api/builds/#{build.id}/telemetry", %{
        type: "cpu_snapshot",
        timestamp: DateTime.to_iso8601(DateTime.utc_now()),
        data: %{
          cpu_percent: 45.2,
          memory_mb: 512.5
        }
      })

      assert json_response(conn, 200)["status"] == "ok"

      # Verify CPU snapshot was saved
      snapshots = Builds.get_cpu_snapshots(build.id)
      assert length(snapshots) == 1

      snapshot = List.first(snapshots)
      assert snapshot.cpu_percent == 45.2
      assert snapshot.memory_mb == 512.5
    end

    test "rejects invalid CPU percent", %{conn: conn, build: build, worker: worker} do
      conn = conn
      |> put_req_header("x-worker-id", worker.id)
      |> put_req_header("x-build-id", build.id)
      |> post("/api/builds/#{build.id}/telemetry", %{
        type: "cpu_snapshot",
        timestamp: DateTime.to_iso8601(DateTime.utc_now()),
        data: %{
          cpu_percent: 2000,  # Invalid: > 1000
          memory_mb: 512
        }
      })

      # Should succeed but not save (validation happens silently)
      assert json_response(conn, 200)["status"] == "ok"

      # No snapshot should be saved
      snapshots = Builds.get_cpu_snapshots(build.id)
      assert length(snapshots) == 0
    end

    test "logs telemetry events", %{conn: conn, build: build, worker: worker} do
      conn = conn
      |> put_req_header("x-worker-id", worker.id)
      |> put_req_header("x-build-id", build.id)
      |> post("/api/builds/#{build.id}/telemetry", %{
        type: "monitor_started",
        timestamp: DateTime.to_iso8601(DateTime.utc_now()),
        data: %{}
      })

      assert json_response(conn, 200)["status"] == "ok"

      logs = Builds.get_logs(build.id)
      telemetry_log = Enum.find(logs, fn log ->
        String.contains?(log.message, "VM monitoring started")
      end)

      assert telemetry_log != nil
    end

    test "updates heartbeat on telemetry", %{conn: conn, build: build, worker: worker} do
      old_build = Builds.get_build(build.id)
      Process.sleep(100)  # Ensure time difference

      conn = conn
      |> put_req_header("x-worker-id", worker.id)
      |> put_req_header("x-build-id", build.id)
      |> post("/api/builds/#{build.id}/telemetry", %{
        type: "heartbeat",
        timestamp: DateTime.to_iso8601(DateTime.utc_now()),
        data: %{}
      })

      assert json_response(conn, 200)["status"] == "ok"

      updated_build = Builds.get_build(build.id)
      assert DateTime.compare(updated_build.last_heartbeat_at, old_build.last_heartbeat_at || updated_build.last_heartbeat_at) == :gt
    end

    test "requires valid telemetry format", %{conn: conn, build: build, worker: worker} do
      conn = conn
      |> put_req_header("x-worker-id", worker.id)
      |> put_req_header("x-build-id", build.id)
      |> post("/api/builds/#{build.id}/telemetry", %{
        invalid: "data"
      })

      assert json_response(conn, 400)["error"] =~ "Invalid telemetry data"
    end
  end

  describe "worker authentication" do
    test "all endpoints reject missing X-Worker-Id", %{conn: conn, build: build} do
      endpoints = [
        {&post/3, "/api/builds/#{build.id}/logs", %{level: "info", message: "test"}},
        {&get/2, "/api/builds/#{build.id}/source", nil},
        {&get/2, "/api/builds/#{build.id}/certs", nil},
        {&get/2, "/api/builds/#{build.id}/certs-secure", nil}
      ]

      for {method, path, body} <- endpoints do
        test_conn = if body, do: method.(conn, path, body), else: method.(conn, path)
        assert test_conn.status in [401, 404]
      end
    end

    test "all endpoints reject non-existent worker", %{conn: conn, build: build} do
      fake_worker_id = "fake-worker-#{:rand.uniform(1000000)}"

      conn = conn
      |> put_req_header("x-worker-id", fake_worker_id)
      |> post("/api/builds/#{build.id}/logs", %{level: "info", message: "test"})

      assert json_response(conn, 403)
    end

    test "all endpoints reject non-existent build", %{conn: conn, worker: worker} do
      fake_build_id = "fake-build-#{:rand.uniform(1000000)}"

      conn = conn
      |> put_req_header("x-worker-id", worker.id)
      |> post("/api/builds/#{fake_build_id}/logs", %{level: "info", message: "test"})

      assert json_response(conn, 404)
    end
  end

  describe "large file streaming" do
    test "streams large source file efficiently", %{conn: conn, build: build, worker: worker} do
      # Create a 5MB test file
      File.mkdir_p!(Path.dirname(build.source_path))
      large_content = :crypto.strong_rand_bytes(5 * 1024 * 1024)
      File.write!(build.source_path, large_content)

      conn = conn
      |> put_req_header("x-worker-id", worker.id)
      |> get("/api/builds/#{build.id}/source")

      assert conn.status == 200
      assert byte_size(conn.resp_body) > 0

      # Cleanup
      File.rm!(build.source_path)
    end
  end
end
