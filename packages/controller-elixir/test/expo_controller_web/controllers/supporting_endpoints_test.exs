defmodule ExpoControllerWeb.SupportingEndpointsTest do
  use ExpoControllerWeb.ConnCase, async: false

  alias ExpoController.{Builds, Workers, Repo}
  alias ExpoController.Storage.FileStorage

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

  describe "GET /api/builds/active" do
    test "returns empty list when no active builds", %{conn: conn} do
      conn = get(conn, ~p"/api/builds/active")

      assert json_response(conn, 200) == %{
        "builds" => []
      }
    end

    test "returns only assigned and building builds", %{conn: conn} do
      # Create builds with various statuses
      {:ok, pending} = Builds.create_build(%{platform: :ios})
      {:ok, assigned} = Builds.create_build(%{platform: :android})
      {:ok, building} = Builds.create_build(%{platform: :ios})
      {:ok, completed} = Builds.create_build(%{platform: :android})
      {:ok, failed} = Builds.create_build(%{platform: :ios})

      # Update statuses
      Repo.update!(Ecto.Changeset.change(assigned, status: :assigned))
      Repo.update!(Ecto.Changeset.change(building, status: :building))
      Repo.update!(Ecto.Changeset.change(completed, status: :completed))
      Repo.update!(Ecto.Changeset.change(failed, status: :failed))

      conn = get(conn, ~p"/api/builds/active")
      response = json_response(conn, 200)

      assert length(response["builds"]) == 2
      ids = Enum.map(response["builds"], & &1["id"])
      assert assigned.id in ids
      assert building.id in ids
      refute pending.id in ids
      refute completed.id in ids
      refute failed.id in ids
    end

    test "includes correct fields in response", %{conn: conn} do
      {:ok, build} = Builds.create_build(%{platform: :ios})
      {:ok, worker} = Workers.register_worker(%{
        id: Ecto.UUID.generate(),
        name: "Test Worker"
      })

      Builds.assign_to_worker(build, worker.id)

      conn = get(conn, ~p"/api/builds/active")
      response = json_response(conn, 200)

      assert [active_build] = response["builds"]
      assert active_build["id"] == build.id
      assert active_build["status"] == "assigned"
      assert active_build["platform"] == "ios"
      assert active_build["worker_id"] == worker.id
      assert is_binary(active_build["started_at"])
    end
  end

  describe "GET /api/workers/:id/stats" do
    test "returns 404 for non-existent worker", %{conn: conn} do
      conn = get(conn, ~p"/api/workers/nonexistent/stats")
      assert json_response(conn, 404) == %{"error" => "Worker not found"}
    end

    test "returns stats for existing worker", %{conn: conn} do
      {:ok, worker} = Workers.register_worker(%{
        id: Ecto.UUID.generate(),
        name: "Test Worker",
        capabilities: %{}
      })

      # Update build counters
      Repo.update!(Ecto.Changeset.change(worker, builds_completed: 10, builds_failed: 2))

      conn = get(conn, ~p"/api/workers/#{worker.id}/stats")
      response = json_response(conn, 200)

      assert response["totalBuilds"] == 12
      assert response["successfulBuilds"] == 10
      assert response["failedBuilds"] == 2
      assert response["workerName"] == "Test Worker"
      assert response["status"] == "idle"
      assert is_binary(response["uptime"])
    end

    test "formats uptime correctly for days", %{conn: conn} do
      {:ok, worker} = Workers.register_worker(%{
        id: Ecto.UUID.generate(),
        name: "Test Worker"
      })

      # Set inserted_at to 2 days + 5 hours ago
      past = DateTime.add(DateTime.utc_now(), -(2 * 24 * 3600 + 5 * 3600), :second) |> DateTime.truncate(:second)
      Repo.update!(Ecto.Changeset.change(worker, inserted_at: past))

      conn = get(conn, ~p"/api/workers/#{worker.id}/stats")
      response = json_response(conn, 200)

      assert response["uptime"] =~ ~r/\d+d \d+h/
    end

    test "formats uptime correctly for hours", %{conn: conn} do
      {:ok, worker} = Workers.register_worker(%{
        id: Ecto.UUID.generate(),
        name: "Test Worker"
      })

      # Set inserted_at to 3 hours + 15 minutes ago
      past = DateTime.add(DateTime.utc_now(), -(3 * 3600 + 15 * 60), :second) |> DateTime.truncate(:second)
      Repo.update!(Ecto.Changeset.change(worker, inserted_at: past))

      conn = get(conn, ~p"/api/workers/#{worker.id}/stats")
      response = json_response(conn, 200)

      assert response["uptime"] =~ ~r/\d+h \d+m/
    end

    test "formats uptime correctly for minutes", %{conn: conn} do
      {:ok, worker} = Workers.register_worker(%{
        id: Ecto.UUID.generate(),
        name: "Test Worker"
      })

      # Set inserted_at to 5 minutes + 30 seconds ago
      past = DateTime.add(DateTime.utc_now(), -(5 * 60 + 30), :second) |> DateTime.truncate(:second)
      Repo.update!(Ecto.Changeset.change(worker, inserted_at: past))

      conn = get(conn, ~p"/api/workers/#{worker.id}/stats")
      response = json_response(conn, 200)

      assert response["uptime"] =~ ~r/\d+m \d+s/
    end

    test "formats uptime correctly for seconds", %{conn: conn} do
      {:ok, worker} = Workers.register_worker(%{
        id: Ecto.UUID.generate(),
        name: "Test Worker"
      })

      # Worker just registered
      conn = get(conn, ~p"/api/workers/#{worker.id}/stats")
      response = json_response(conn, 200)

      assert response["uptime"] =~ ~r/\d+s/
    end
  end

  describe "GET /health" do
    test "returns ok status without authentication", %{} do
      # No API key header
      conn = build_conn()
      |> get(~p"/health")

      assert json_response(conn, 200) == %{
        "status" => "ok",
        "queue" => %{
          "pending" => 0,
          "active" => 0
        },
        "storage" => %{}
      }
    end

    test "includes queue stats", %{} do
      # Create builds with different statuses
      {:ok, _pending1} = Builds.create_build(%{platform: :ios})
      {:ok, _pending2} = Builds.create_build(%{platform: :android})
      {:ok, assigned} = Builds.create_build(%{platform: :ios})
      {:ok, building} = Builds.create_build(%{platform: :android})

      Repo.update!(Ecto.Changeset.change(assigned, status: :assigned))
      Repo.update!(Ecto.Changeset.change(building, status: :building))

      conn = build_conn() |> get(~p"/health")
      response = json_response(conn, 200)

      assert response["queue"]["pending"] == 2
      assert response["queue"]["active"] == 2
    end
  end

  describe "POST /api/builds/:id/retry" do
    setup %{conn: conn} do
      # Create original build with source file
      {:ok, original} = Builds.create_build(%{platform: :ios})

      # Create fake source file (relative path for database)
      relative_path = "builds/#{original.id}/source.tar.gz"
      full_path = Path.join(
        Application.get_env(:expo_controller, :storage_root, "./storage"),
        relative_path
      )
      File.mkdir_p!(Path.dirname(full_path))
      File.write!(full_path, "fake source content")

      # Store relative path in database
      original = Repo.update!(Ecto.Changeset.change(original, source_path: relative_path))

      {:ok, conn: conn, original: original}
    end

    test "requires authentication", %{original: original} do
      conn = build_conn()
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/builds/#{original.id}/retry")

      assert json_response(conn, 401)
    end

    test "admin API key allows retry", %{conn: conn, original: original} do
      conn = post(conn, ~p"/api/builds/#{original.id}/retry")

      assert response = json_response(conn, 200)
      assert response["id"] != original.id
      assert response["status"] == "pending"
      assert response["access_token"]
      assert response["original_build_id"] == original.id
    end

    test "build token allows retry", %{original: original} do
      conn = build_conn()
      |> put_req_header("x-build-token", original.access_token)
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/builds/#{original.id}/retry")

      assert response = json_response(conn, 200)
      assert response["id"] != original.id
    end

    test "wrong build token rejects retry", %{original: original} do
      conn = build_conn()
      |> put_req_header("x-build-token", "wrong-token")
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/builds/#{original.id}/retry")

      assert json_response(conn, 403)
    end

    test "copies source to new build", %{conn: conn, original: original} do
      conn = post(conn, ~p"/api/builds/#{original.id}/retry")
      response = json_response(conn, 200)

      new_build = Builds.get_build(response["id"])
      assert new_build.source_path
      assert FileStorage.file_exists?(new_build.source_path)
      assert new_build.source_path != original.source_path
    end

    test "copies certs if present", %{conn: conn, original: original} do
      # Create fake certs file (relative path for database)
      relative_path = "builds/#{original.id}/certs.zip"
      full_path = Path.join(
        Application.get_env(:expo_controller, :storage_root, "./storage"),
        relative_path
      )
      File.mkdir_p!(Path.dirname(full_path))
      File.write!(full_path, "fake certs content")

      # Store relative path in database
      original = Repo.update!(Ecto.Changeset.change(original, certs_path: relative_path))

      conn = post(conn, ~p"/api/builds/#{original.id}/retry")
      response = json_response(conn, 200)

      new_build = Builds.get_build(response["id"])
      assert new_build.certs_path
      assert FileStorage.file_exists?(new_build.certs_path)
    end

    test "generates new access_token", %{conn: conn, original: original} do
      conn = post(conn, ~p"/api/builds/#{original.id}/retry")
      response = json_response(conn, 200)

      new_build = Builds.get_build(response["id"])
      assert new_build.access_token
      assert new_build.access_token != original.access_token
    end

    test "logs retry in both builds", %{conn: conn, original: original} do
      conn = post(conn, ~p"/api/builds/#{original.id}/retry")
      response = json_response(conn, 200)

      original_logs = Builds.get_logs(original.id)
      new_logs = Builds.get_logs(response["id"])

      assert Enum.any?(original_logs, fn log ->
        log.message =~ "Retried as build #{response["id"]}"
      end)

      assert Enum.any?(new_logs, fn log ->
        log.message =~ "Build submitted (retry of #{original.id})"
      end)
    end

    test "returns 404 when original build not found", %{conn: conn} do
      conn = post(conn, ~p"/api/builds/nonexistent/retry")
      assert json_response(conn, 404)
    end

    test "returns 400 when source no longer exists", %{conn: conn} do
      {:ok, build} = Builds.create_build(%{platform: :ios})
      build = Repo.update!(Ecto.Changeset.change(build, source_path: "/nonexistent/path"))

      conn = post(conn, ~p"/api/builds/#{build.id}/retry")
      response = json_response(conn, 400)

      assert response["error"] =~ "source no longer available"
    end
  end
end
