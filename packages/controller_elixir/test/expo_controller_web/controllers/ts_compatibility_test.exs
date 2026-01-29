defmodule ExpoControllerWeb.TsCompatibilityTest do
  use ExpoControllerWeb.ConnCase

  alias ExpoController.{Builds, Workers}
  alias ExpoController.Storage.FileStorage

  setup %{conn: conn} do
    # Set API key for auth
    api_key = "test_api_key"
    Application.put_env(:expo_controller, :api_key, api_key)

    conn = put_req_header(conn, "x-api-key", api_key)

    {:ok, conn: conn, api_key: api_key}
  end

  describe "route registration" do
    test "POST /api/builds/submit is registered (TS compatibility)", %{conn: conn} do
      routes = ExpoControllerWeb.Router.__routes__()

      assert Enum.any?(routes, fn r ->
        r.path == "/api/builds/submit" && r.verb == :post
      end), "POST /api/builds/submit route not found"
    end

    test "POST /api/builds is registered (Phoenix convention)", %{conn: conn} do
      routes = ExpoControllerWeb.Router.__routes__()

      assert Enum.any?(routes, fn r ->
        r.path == "/api/builds" && r.verb == :post
      end), "POST /api/builds route not found"
    end
  end

  describe "GET /api/builds/:id/status (TS compatibility endpoint)" do
    test "route is registered", %{conn: conn} do
      routes = ExpoControllerWeb.Router.__routes__()

      assert Enum.any?(routes, fn r ->
        r.path == "/api/builds/:id/status" && r.verb == :get
      end), "GET /api/builds/:id/status route not found"
    end

    test "returns status in TS format with numeric timestamps", %{conn: conn} do
      {:ok, worker} = Workers.register_worker(%{
        id: "test-worker-status",
        name: "Test Worker",
        capabilities: %{}
      })

      {:ok, build} = Builds.create_build(%{platform: :ios})
      {:ok, build} = Builds.assign_to_worker(build, worker.id)

      conn = get(conn, "/api/builds/#{build.id}/status")

      assert %{
        "id" => id,
        "status" => _status,
        "platform" => "ios",
        "worker_id" => worker_id,
        "submitted_at" => submitted_at,
        "started_at" => started_at,
        "completed_at" => completed_at,
        "error_message" => error_message
      } = json_response(conn, 200)

      assert id == build.id
      assert worker_id == "test-worker-status"

      # TS expects numeric timestamps (milliseconds)
      assert is_integer(submitted_at)
      assert is_integer(started_at) or is_nil(started_at)
      assert is_nil(completed_at) or is_integer(completed_at)
      assert is_nil(error_message)
    end

    test "GET /api/builds/:id still works (Phoenix convention)", %{conn: conn} do
      {:ok, build} = Builds.create_build(%{platform: :android})

      conn = get(conn, "/api/builds/#{build.id}")

      # Full build details with ISO timestamps
      assert %{
        "id" => _id,
        "status" => "pending",
        "platform" => "android",
        "submitted_at" => submitted_at,
        "has_result" => false
      } = json_response(conn, 200)

      # Phoenix format uses ISO8601 strings
      assert is_binary(submitted_at)
      assert String.contains?(submitted_at, "T")
    end
  end

  describe "GET /api/builds/:id/download (TS compatibility - defaults to result)" do
    test "route without type is registered", %{conn: conn} do
      routes = ExpoControllerWeb.Router.__routes__()

      assert Enum.any?(routes, fn r ->
        r.path == "/api/builds/:id/download" && r.verb == :get
      end), "GET /api/builds/:id/download route not found"
    end

    test "route with type is registered", %{conn: conn} do
      routes = ExpoControllerWeb.Router.__routes__()

      assert Enum.any?(routes, fn r ->
        r.path == "/api/builds/:id/download/:type" && r.verb == :get
      end), "GET /api/builds/:id/download/:type route not found"
    end

    test "GET /api/builds/:id/download returns 404 for build without result", %{conn: conn} do
      {:ok, build} = Builds.create_build(%{platform: :ios})

      conn = get(conn, "/api/builds/#{build.id}/download")

      # Build exists but has no result yet
      assert json_response(conn, 404)["error"] =~ ~r/not found/i
    end
  end

  describe "POST /api/workers/upload (TS compatibility alias)" do
    test "upload route is registered", %{conn: conn} do
      routes = ExpoControllerWeb.Router.__routes__()

      assert Enum.any?(routes, fn r ->
        r.path == "/api/workers/upload" && r.verb == :post
      end), "POST /api/workers/upload route not found"
    end

    test "result route is registered", %{conn: conn} do
      routes = ExpoControllerWeb.Router.__routes__()

      assert Enum.any?(routes, fn r ->
        r.path == "/api/workers/result" && r.verb == :post
      end), "POST /api/workers/result route not found"
    end
  end

  describe "comprehensive path compatibility" do
    test "all TS paths work alongside Phoenix paths", %{conn: conn} do
      # Test that both path styles are registered
      routes = ExpoControllerWeb.Router.__routes__()

      # POST /api/builds/submit (TS) and POST /api/builds (Phoenix)
      assert Enum.any?(routes, fn r ->
        r.path == "/api/builds/submit" && r.verb == :post
      end)
      assert Enum.any?(routes, fn r ->
        r.path == "/api/builds" && r.verb == :post
      end)

      # GET /api/builds/:id/status (TS) and GET /api/builds/:id (Phoenix)
      assert Enum.any?(routes, fn r ->
        r.path == "/api/builds/:id/status" && r.verb == :get
      end)
      assert Enum.any?(routes, fn r ->
        r.path == "/api/builds/:id" && r.verb == :get
      end)

      # GET /api/builds/:id/download (TS) and GET /api/builds/:id/download/:type (Phoenix)
      assert Enum.any?(routes, fn r ->
        r.path == "/api/builds/:id/download" && r.verb == :get
      end)
      assert Enum.any?(routes, fn r ->
        r.path == "/api/builds/:id/download/:type" && r.verb == :get
      end)

      # POST /api/workers/upload (TS) and POST /api/workers/result (Phoenix)
      assert Enum.any?(routes, fn r ->
        r.path == "/api/workers/upload" && r.verb == :post
      end)
      assert Enum.any?(routes, fn r ->
        r.path == "/api/workers/result" && r.verb == :post
      end)
    end
  end
end
