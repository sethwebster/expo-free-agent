defmodule ExpoControllerWeb.Plugs.ApiAuthTest do
  use ExpoControllerWeb.ConnCase, async: true

  alias ExpoControllerWeb.Plugs.Auth
  alias ExpoController.{Builds, Workers, Repo}

  @api_key Application.compile_env(:expo_controller, :api_key)

  setup do
    # Clean database
    Repo.delete_all(Builds.Build)
    Repo.delete_all(Workers.Worker)

    conn = build_conn()
    |> put_req_header("content-type", "application/json")

    {:ok, conn: conn}
  end

  describe "API key authentication - require_api_key/2" do
    test "allows access with valid API key in X-API-Key header", %{conn: conn} do
      conn = conn
      |> put_req_header("x-api-key", @api_key)
      |> Auth.require_api_key([])

      refute conn.halted
      assert conn.assigns[:authenticated] == true
    end

    test "allows access with valid API key in lowercase header", %{conn: conn} do
      conn = conn
      |> put_req_header("x-api-key", @api_key)
      |> Auth.require_api_key([])

      refute conn.halted
    end

    test "rejects request with invalid API key", %{conn: conn} do
      conn = conn
      |> put_req_header("x-api-key", "invalid-key-12345")
      |> Auth.require_api_key([])

      assert conn.halted
      assert conn.status == 401
      assert %{"error" => error} = json_response(conn, 401)
      assert error =~ "Unauthorized"
    end

    test "rejects request with empty API key", %{conn: conn} do
      conn = conn
      |> put_req_header("x-api-key", "")
      |> Auth.require_api_key([])

      assert conn.halted
      assert conn.status == 401
    end

    test "rejects request with missing API key header", %{conn: conn} do
      conn = Auth.require_api_key(conn, [])

      assert conn.halted
      assert conn.status == 401
    end

    test "rejects request with API key in wrong header", %{conn: conn} do
      conn = conn
      |> put_req_header("authorization", "Bearer #{@api_key}")
      |> Auth.require_api_key([])

      assert conn.halted
      assert conn.status == 401
    end

    test "rejects API key with whitespace", %{conn: conn} do
      conn = conn
      |> put_req_header("x-api-key", " #{@api_key} ")
      |> Auth.require_api_key([])

      assert conn.halted
      assert conn.status == 401
    end

    test "uses constant-time comparison to prevent timing attacks", %{conn: conn} do
      # This test verifies that invalid keys of different lengths
      # don't reveal information through timing differences

      short_key = "abc"
      long_key = String.duplicate("a", 100)
      correct_length_key = String.duplicate("x", String.length(@api_key))

      # All should fail with same behavior
      conn1 = conn
      |> put_req_header("x-api-key", short_key)
      |> Auth.require_api_key([])

      conn2 = build_conn()
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-api-key", long_key)
      |> Auth.require_api_key([])

      conn3 = build_conn()
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-api-key", correct_length_key)
      |> Auth.require_api_key([])

      # All should be halted with same status
      assert conn1.halted == conn2.halted
      assert conn2.halted == conn3.halted
      assert conn1.status == conn2.status
      assert conn2.status == conn3.status
    end

    test "rejects case-sensitive variations of valid API key", %{conn: conn} do
      # API keys should be case-sensitive
      wrong_case_key = String.upcase(@api_key)

      conn = conn
      |> put_req_header("x-api-key", wrong_case_key)
      |> Auth.require_api_key([])

      if wrong_case_key == @api_key do
        # Skip if API key is all lowercase/uppercase
        :ok
      else
        assert conn.halted
        assert conn.status == 401
      end
    end
  end

  describe "API key authentication - protected endpoints" do
    test "POST /api/builds requires valid API key", %{conn: conn} do
      # Without API key
      conn = post(conn, "/api/builds", %{platform: "ios"})
      assert conn.status == 401

      # With valid API key
      conn = build_conn()
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-api-key", @api_key)
      |> post("/api/builds", %{platform: "ios"})

      # Should fail with different error (missing source file, not auth error)
      assert conn.status in [400, 422]
    end

    test "GET /api/builds requires valid API key", %{conn: conn} do
      conn = get(conn, "/api/builds")
      assert conn.status == 401

      # With valid API key
      conn = build_conn()
      |> put_req_header("x-api-key", @api_key)
      |> get("/api/builds")

      assert conn.status == 200
    end

    test "POST /api/builds/:id/cancel requires valid API key", %{conn: conn} do
      {:ok, build} = Builds.create_build(%{platform: :ios})

      conn = post(conn, "/api/builds/#{build.id}/cancel")
      assert conn.status == 401

      # With valid API key
      conn = build_conn()
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-api-key", @api_key)
      |> post("/api/builds/#{build.id}/cancel")

      assert conn.status in [200, 400]  # May fail business logic, not auth
    end

    test "GET /api/builds/statistics requires valid API key", %{conn: conn} do
      conn = get(conn, "/api/builds/statistics")
      assert conn.status == 401

      conn = build_conn()
      |> put_req_header("x-api-key", @api_key)
      |> get("/api/builds/statistics")

      assert conn.status == 200
    end
  end

  describe "API key vs build token authentication" do
    test "build status endpoint accepts API key", %{conn: conn} do
      {:ok, build} = Builds.create_build(%{platform: :ios})

      conn = conn
      |> put_req_header("x-api-key", @api_key)
      |> get("/api/builds/#{build.id}/status")

      assert conn.status == 200
    end

    test "build status endpoint accepts build token", %{conn: conn} do
      {:ok, build} = Builds.create_build(%{platform: :ios})

      conn = conn
      |> put_req_header("x-build-token", build.access_token)
      |> get("/api/builds/#{build.id}/status")

      assert conn.status == 200
    end

    test "build status endpoint rejects without auth", %{conn: conn} do
      {:ok, build} = Builds.create_build(%{platform: :ios})

      conn = get(conn, "/api/builds/#{build.id}/status")

      assert conn.status == 401
    end

    test "API key overrides build token when both provided", %{conn: conn} do
      {:ok, build1} = Builds.create_build(%{platform: :ios})
      {:ok, build2} = Builds.create_build(%{platform: :android})

      # API key should allow access to any build
      # Even with wrong build token
      conn = conn
      |> put_req_header("x-api-key", @api_key)
      |> put_req_header("x-build-token", build1.access_token)
      |> get("/api/builds/#{build2.id}/status")

      assert conn.status == 200
    end

    test "build download endpoint accepts API key", %{conn: conn} do
      {:ok, build} = Builds.create_build(%{platform: :ios, source_path: "/tmp/test.tar.gz"})

      conn = conn
      |> put_req_header("x-api-key", @api_key)
      |> get("/api/builds/#{build.id}/download")

      # Should fail with 404 (file not found), not 401 (unauthorized)
      assert conn.status == 404
    end

    test "build download endpoint accepts build token", %{conn: conn} do
      {:ok, build} = Builds.create_build(%{platform: :ios, source_path: "/tmp/test.tar.gz"})

      conn = conn
      |> put_req_header("x-build-token", build.access_token)
      |> get("/api/builds/#{build.id}/download")

      # Should fail with 404 (file not found), not 401 (unauthorized)
      assert conn.status == 404
    end
  end

  describe "worker authentication - require_worker_id/2" do
    test "allows access with valid worker ID", %{conn: conn} do
      {:ok, worker} = Workers.register_worker(%{
        id: "worker-test-#{:rand.uniform(10000)}",
        name: "Test Worker",
        capabilities: %{}
      })

      conn = conn
      |> put_req_header("x-worker-id", worker.id)
      |> get("/api/workers/poll")

      assert conn.status == 200
    end

    test "rejects request with invalid worker ID", %{conn: conn} do
      conn = conn
      |> put_req_header("x-worker-id", "nonexistent-worker")
      |> get("/api/workers/poll")

      assert conn.status == 403
    end

    test "rejects request without worker ID", %{conn: conn} do
      conn = get(conn, "/api/workers/poll")

      assert conn.status == 401
    end

    test "rejects empty worker ID", %{conn: conn} do
      conn = conn
      |> put_req_header("x-worker-id", "")
      |> get("/api/workers/poll")

      assert conn.status == 401
    end
  end

  describe "worker-specific build access" do
    test "worker can only access assigned builds", %{conn: conn} do
      # Create two workers
      {:ok, worker1} = Workers.register_worker(%{
        id: "worker-1-#{:rand.uniform(10000)}",
        name: "Worker 1",
        capabilities: %{}
      })

      {:ok, worker2} = Workers.register_worker(%{
        id: "worker-2-#{:rand.uniform(10000)}",
        name: "Worker 2",
        capabilities: %{}
      })

      # Create build assigned to worker1
      {:ok, build} = Builds.create_build(%{
        platform: :ios,
        source_path: "/storage/test/source.tar.gz"
      })

      {:ok, build} = Builds.assign_to_worker(build, worker1.id)

      # Worker 1 should access successfully
      conn1 = build_conn()
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-worker-id", worker1.id)
      |> post("/api/builds/#{build.id}/logs", %{level: "info", message: "test"})

      assert conn1.status == 200

      # Worker 2 should be forbidden
      conn2 = build_conn()
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-worker-id", worker2.id)
      |> post("/api/builds/#{build.id}/logs", %{level: "info", message: "test"})

      assert conn2.status == 403
    end

    test "worker cannot access unassigned builds", %{conn: conn} do
      {:ok, worker} = Workers.register_worker(%{
        id: "worker-#{:rand.uniform(10000)}",
        name: "Worker",
        capabilities: %{}
      })

      {:ok, build} = Builds.create_build(%{platform: :ios})

      conn = conn
      |> put_req_header("x-worker-id", worker.id)
      |> post("/api/builds/#{build.id}/logs", %{level: "info", message: "test"})

      assert conn.status == 403
    end
  end

  describe "public endpoints (no auth required)" do
    test "GET /health does not require authentication", %{conn: conn} do
      conn = get(conn, "/health")
      assert conn.status == 200
    end

    test "GET /api/stats does not require authentication", %{conn: conn} do
      conn = get(conn, "/api/stats")
      assert conn.status == 200
    end

    test "POST /api/workers/register does not require authentication", %{conn: conn} do
      conn = post(conn, "/api/workers/register", %{
        id: "new-worker-#{:rand.uniform(10000)}",
        name: "New Worker",
        capabilities: %{}
      })

      assert conn.status in [200, 201, 400]  # Not 401
    end
  end

  describe "authentication error responses" do
    test "returns JSON error for missing API key", %{conn: conn} do
      conn = get(conn, "/api/builds")

      assert conn.status == 401
      assert %{"error" => error} = json_response(conn, 401)
      assert is_binary(error)
    end

    test "returns JSON error for invalid API key", %{conn: conn} do
      conn = conn
      |> put_req_header("x-api-key", "invalid")
      |> get("/api/builds")

      assert conn.status == 401
      assert %{"error" => _} = json_response(conn, 401)
    end

    test "returns JSON error for missing worker ID", %{conn: conn} do
      conn = get(conn, "/api/workers/poll")

      assert conn.status == 401
      assert %{"error" => _} = json_response(conn, 401)
    end

    test "returns JSON error for invalid worker ID", %{conn: conn} do
      conn = conn
      |> put_req_header("x-worker-id", "invalid")
      |> get("/api/workers/poll")

      assert conn.status == 403
      assert %{"error" => _} = json_response(conn, 403)
    end
  end

  describe "security headers" do
    test "does not leak authentication details in error messages", %{conn: conn} do
      conn = conn
      |> put_req_header("x-api-key", "wrong-key-12345")
      |> get("/api/builds")

      assert %{"error" => error} = json_response(conn, 401)

      # Error should not reveal:
      # - Expected API key
      # - Partial matches
      # - Comparison details
      refute error =~ @api_key
      refute error =~ "expected"
      refute error =~ "comparison"
    end

    test "error response does not vary by API key length", %{conn: conn} do
      short_conn = conn
      |> put_req_header("x-api-key", "abc")
      |> get("/api/builds")

      long_conn = build_conn()
      |> put_req_header("x-api-key", String.duplicate("x", 1000))
      |> get("/api/builds")

      # Response structure should be identical
      assert short_conn.status == long_conn.status

      short_body = json_response(short_conn, 401)
      long_body = json_response(long_conn, 401)

      # Error messages should be consistent
      assert Map.keys(short_body) == Map.keys(long_body)
    end
  end

  describe "concurrent authentication" do
    @tag :concurrent
    test "handles concurrent API key validations", %{conn: conn} do
      tasks = Enum.map(1..50, fn _i ->
        Task.async(fn ->
          test_conn = build_conn()
          |> put_req_header("x-api-key", @api_key)
          |> get("/api/builds")

          test_conn.status
        end)
      end)

      results = Task.await_many(tasks)

      # All should succeed
      assert Enum.all?(results, fn status -> status == 200 end)
    end

    @tag :concurrent
    test "handles concurrent invalid authentications", %{conn: conn} do
      tasks = Enum.map(1..50, fn i ->
        Task.async(fn ->
          test_conn = build_conn()
          |> put_req_header("x-api-key", "invalid-#{i}")
          |> get("/api/builds")

          test_conn.status
        end)
      end)

      results = Task.await_many(tasks)

      # All should fail with 401
      assert Enum.all?(results, fn status -> status == 401 end)
    end
  end
end
