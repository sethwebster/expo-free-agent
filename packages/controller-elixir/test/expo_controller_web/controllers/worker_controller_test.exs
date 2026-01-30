defmodule ExpoControllerWeb.WorkerControllerTest do
  use ExpoControllerWeb.ConnCase, async: false

  import Ecto.Query

  alias ExpoController.{Builds, Workers, Repo}

  @api_key Application.compile_env(:expo_controller, :api_key)

  setup do
    # Clean database before each test
    Repo.delete_all(Builds.Build)
    Repo.delete_all(Workers.Worker)

    conn = build_conn()
    |> put_req_header("x-api-key", @api_key)
    |> put_req_header("content-type", "application/json")

    {:ok, conn: conn}
  end

  describe "concurrent worker poll" do
    test "concurrent polls assign builds uniquely (no double assignment)", %{conn: conn} do
      # Create 10 pending builds
      builds = for i <- 1..10 do
        {:ok, build} = Builds.create_build(%{
          platform: "ios",
          source_path: "source_#{i}",
          status: :pending
        })
        build
      end

      # Create 20 workers
      workers = for i <- 1..20 do
        {:ok, worker} = Workers.register_worker(%{
          id: Ecto.UUID.generate(),
          name: "Worker-#{i}",
          capabilities: %{}
        })
        worker
      end

      # Spawn 20 tasks polling simultaneously
      tasks = Enum.map(workers, fn worker ->
        Task.async(fn ->
          conn = build_conn()
          |> put_req_header("x-api-key", @api_key)
          |> put_req_header("content-type", "application/json")

          get(conn, "/api/workers/poll?worker_id=#{worker.id}")
        end)
      end)

      # Wait for all tasks to complete (max 10 seconds)
      results = Task.await_many(tasks, 10_000)

      # Extract job assignments
      jobs = Enum.map(results, fn conn ->
        assert conn.status == 200
        json_response(conn, 200)["job"]
      end)

      assigned = Enum.reject(jobs, &is_nil/1)

      # CRITICAL: Each build assigned exactly once
      assigned_ids = Enum.map(assigned, & &1["id"])
      unique_ids = Enum.uniq(assigned_ids)

      assert length(assigned_ids) == length(unique_ids),
        "Race condition detected: #{length(assigned_ids) - length(unique_ids)} builds were assigned multiple times. " <>
        "Assigned: #{inspect(assigned_ids)}"

      # Should assign exactly 10 builds (we have 10 pending, 20 workers)
      assert length(assigned) == 10,
        "Expected 10 assignments, got #{length(assigned)}"

      # Verify DB consistency
      db_assigned = Repo.all(
        from b in Builds.Build,
        where: b.status in [:assigned, :building]
      )

      assert length(db_assigned) == length(assigned),
        "Queue state diverged from DB state: #{length(db_assigned)} in DB, #{length(assigned)} assigned"

      # Verify each build has unique worker
      worker_ids = Enum.map(db_assigned, & &1.worker_id)
      assert length(worker_ids) == length(Enum.uniq(worker_ids)),
        "Some workers were assigned multiple builds"
    end

    test "concurrent polls with limited builds handles contention correctly", %{conn: conn} do
      # Create only 1 pending build
      {:ok, build} = Builds.create_build(%{
        platform: "ios",
        source_path: "source_1",
        status: :pending
      })

      # Create 10 workers competing for 1 build
      workers = for i <- 1..10 do
        {:ok, worker} = Workers.register_worker(%{
          id: Ecto.UUID.generate(),
          name: "Worker-#{i}",
          capabilities: %{}
        })
        worker
      end

      # Spawn 10 tasks polling simultaneously
      tasks = Enum.map(workers, fn worker ->
        Task.async(fn ->
          conn = build_conn()
          |> put_req_header("x-api-key", @api_key)
          |> put_req_header("content-type", "application/json")

          get(conn, "/api/workers/poll?worker_id=#{worker.id}")
        end)
      end)

      results = Task.await_many(tasks, 10_000)

      # Extract job assignments
      jobs = Enum.map(results, fn conn ->
        assert conn.status == 200
        json_response(conn, 200)["job"]
      end)

      assigned = Enum.reject(jobs, &is_nil/1)
      not_assigned = Enum.filter(jobs, &is_nil/1)

      # Exactly 1 build should be assigned
      assert length(assigned) == 1, "Expected 1 assignment, got #{length(assigned)}"

      # 9 workers should get nil
      assert length(not_assigned) == 9, "Expected 9 nil responses, got #{length(not_assigned)}"

      # Verify the build was assigned to exactly one worker
      db_build = Repo.get!(Builds.Build, build.id)
      assert db_build.status in [:assigned, :building]
      assert db_build.worker_id in Enum.map(workers, & &1.id)
    end

    test "transaction timeout doesn't hang", %{conn: conn} do
      # This test ensures transactions timeout correctly
      # Create a build
      {:ok, build} = Builds.create_build(%{
        platform: "ios",
        source_path: "source_1",
        status: :pending
      })

      # Create a worker
      {:ok, worker} = Workers.register_worker(%{
        id: Ecto.UUID.generate(),
        name: "Worker-1",
        capabilities: %{}
      })

      # Poll should complete within reasonable time (not hang)
      task = Task.async(fn ->
        conn = build_conn()
        |> put_req_header("x-api-key", @api_key)
        |> put_req_header("content-type", "application/json")

        get(conn, "/api/workers/poll?worker_id=#{worker.id}")
      end)

      # Should complete within 6 seconds (5 second transaction timeout + 1 second buffer)
      assert {:ok, result} = Task.yield(task, 6_000)
      assert result.status == 200
    end
  end

  describe "register worker" do
    test "registers new worker", %{conn: conn} do
      worker_id = Ecto.UUID.generate()

      conn = post(conn, "/api/workers/register", %{
        id: worker_id,
        name: "Test Worker",
        capabilities: %{platform: "ios"}
      })

      assert %{
        "id" => ^worker_id,
        "status" => "registered"
      } = json_response(conn, 200)

      # Verify worker exists in DB
      assert Workers.get_worker(worker_id)
    end

    test "REGRESSION: worker can poll immediately after registration with nanoid", %{conn: conn} do
      # This tests the bug where worker registers with nanoid but poll returns 404
      worker_id = Nanoid.generate()

      # Step 1: Register worker (conn already has API key from setup)
      register_conn = post(conn, "/api/workers/register", %{
        id: worker_id,
        name: "Immediate Poll Test",
        capabilities: %{platform: "ios"}
      })

      register_response = json_response(register_conn, 200)
      assert register_response["id"] == worker_id
      assert register_response["status"] == "registered"

      # Verify worker was actually saved to database
      db_worker = Workers.get_worker(worker_id)
      assert db_worker != nil, "Worker not found in database immediately after registration"
      assert db_worker.id == worker_id

      # Step 2: Poll immediately (should not 404)
      poll_conn = build_conn()
        |> put_req_header("x-api-key", @api_key)
        |> get("/api/workers/poll?worker_id=#{worker_id}")

      # Should return 200 with no job (not 404)
      response = json_response(poll_conn, 200)
      assert response["job"] == nil, "Expected no job, worker should be found but no builds pending"
    end

    test "REGRESSION: worker can poll immediately after registration with UUID", %{conn: conn} do
      # Ensure UUID format also works
      worker_id = Ecto.UUID.generate()

      # Register (conn already has API key from setup)
      register_conn = post(conn, "/api/workers/register", %{
        id: worker_id,
        name: "UUID Poll Test",
        capabilities: %{}
      })

      register_response = json_response(register_conn, 200)
      assert register_response["id"] == worker_id

      # Verify in DB
      assert Workers.get_worker(worker_id) != nil

      # Poll immediately
      poll_conn = build_conn()
        |> put_req_header("x-api-key", @api_key)
        |> get("/api/workers/poll?worker_id=#{worker_id}")

      assert json_response(poll_conn, 200)
    end

    test "updates existing worker", %{conn: conn} do
      worker_id = Ecto.UUID.generate()

      # Register first time
      {:ok, _worker} = Workers.register_worker(%{
        id: worker_id,
        name: "Old Name",
        capabilities: %{}
      })

      # Register again with same ID - should re-register
      conn = post(conn, "/api/workers/register", %{
        id: worker_id,
        name: "New Name",
        capabilities: %{platform: "ios"}
      })

      assert %{
        "id" => ^worker_id,
        "status" => "re-registered"
      } = json_response(conn, 200)

      # Verify heartbeat was updated but name stays the same
      # (re-registration updates heartbeat but doesn't change name)
      worker = Workers.get_worker(worker_id)
      assert worker.name == "Old Name"
    end

    test "REGRESSION: re-registration is idempotent", %{conn: conn} do
      # First registration without ID - controller assigns one
      first_conn = post(conn, "/api/workers/register", %{
        name: "Test Worker",
        capabilities: %{platform: "ios"}
      })

      first_response = json_response(first_conn, 200)
      worker_id = first_response["id"]
      assert first_response["status"] == "registered"

      # Simulate app restart - worker sends existing ID for re-registration
      second_conn = post(conn, "/api/workers/register", %{
        id: worker_id,
        name: "Test Worker",
        capabilities: %{platform: "ios"}
      })

      second_response = json_response(second_conn, 200)
      assert second_response["id"] == worker_id, "Re-registration should return same ID"
      assert second_response["status"] == "re-registered", "Status should indicate re-registration"

      # Verify only one worker record exists
      assert length(Workers.list_workers()) == 1

      # Verify worker can poll immediately after re-registration
      poll_conn = build_conn()
        |> put_req_header("x-api-key", @api_key)
        |> get("/api/workers/poll?worker_id=#{worker_id}")

      assert json_response(poll_conn, 200)
    end
  end

  describe "upload result" do
    setup %{conn: conn} do
      # Create worker and build
      {:ok, worker} = Workers.register_worker(%{
        id: Ecto.UUID.generate(),
        name: "Test Worker",
        capabilities: %{}
      })

      {:ok, build} = Builds.create_build(%{
        platform: "ios",
        source_path: "source",
        status: :pending
      })

      {:ok, build} = Builds.assign_to_worker(build, worker.id)

      {:ok, worker: worker, build: build, conn: put_req_header(conn, "x-worker-id", worker.id)}
    end

    test "uploads build result successfully", %{conn: conn, build: build} do
      # Create a temporary file to upload
      result_content = "test result content"
      {:ok, tmp_path} = Plug.Upload.random_file("result")
      File.write!(tmp_path, result_content)

      upload = %Plug.Upload{
        path: tmp_path,
        filename: "result.tar.gz"
      }

      conn = post(conn, "/api/workers/result", %{
        "build_id" => build.id,
        "result" => upload
      })

      assert %{"success" => true} = json_response(conn, 200)

      # Verify build is completed
      updated_build = Builds.get_build(build.id)
      assert updated_build.status == :completed
      assert updated_build.result_path

      # Cleanup
      File.rm(tmp_path)
    end

    test "returns error for missing build", %{conn: conn} do
      fake_id = Ecto.UUID.generate()

      conn = post(conn, "/api/workers/result", %{
        "build_id" => fake_id,
        "result" => %Plug.Upload{path: "/tmp/fake", filename: "result.tar.gz"}
      })

      assert %{"error" => "Build not found"} = json_response(conn, 404)
    end
  end

  describe "report failure" do
    setup %{conn: conn} do
      {:ok, worker} = Workers.register_worker(%{
        id: Ecto.UUID.generate(),
        name: "Test Worker",
        capabilities: %{}
      })

      {:ok, build} = Builds.create_build(%{
        platform: "ios",
        source_path: "source",
        status: :pending
      })

      {:ok, build} = Builds.assign_to_worker(build, worker.id)

      {:ok, worker: worker, build: build, conn: put_req_header(conn, "x-worker-id", worker.id)}
    end

    test "marks build as failed", %{conn: conn, build: build} do
      conn = post(conn, "/api/workers/fail", %{
        "build_id" => build.id,
        "error" => "Build failed due to error"
      })

      assert %{"success" => true} = json_response(conn, 200)

      # Verify build is failed
      updated_build = Builds.get_build(build.id)
      assert updated_build.status == :failed
      assert updated_build.error_message == "Build failed due to error"
    end
  end

  describe "heartbeat" do
    setup %{conn: conn} do
      {:ok, worker} = Workers.register_worker(%{
        id: Ecto.UUID.generate(),
        name: "Test Worker",
        capabilities: %{}
      })

      {:ok, build} = Builds.create_build(%{
        platform: "ios",
        source_path: "source",
        status: :pending
      })

      {:ok, build} = Builds.assign_to_worker(build, worker.id)

      {:ok, worker: worker, build: build, conn: put_req_header(conn, "x-worker-id", worker.id)}
    end

    test "records heartbeat successfully", %{conn: conn, build: build} do
      old_heartbeat = build.last_heartbeat_at

      # Wait a moment to ensure timestamp changes
      Process.sleep(100)

      conn = post(conn, "/api/workers/heartbeat", %{
        "build_id" => build.id
      })

      assert %{"success" => true} = json_response(conn, 200)

      # Verify heartbeat was updated
      updated_build = Builds.get_build(build.id)

      if old_heartbeat do
        assert DateTime.compare(updated_build.last_heartbeat_at, old_heartbeat) == :gt
      else
        assert updated_build.last_heartbeat_at
      end
    end
  end
end
