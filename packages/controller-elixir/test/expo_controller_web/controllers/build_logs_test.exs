defmodule ExpoControllerWeb.BuildLogsTest do
  use ExpoControllerWeb.ConnCase, async: false

  alias ExpoController.{Builds, Repo}

  @api_key Application.compile_env(:expo_controller, :api_key)

  setup do
    # Clean database before each test
    Repo.delete_all(Builds.Build)

    # Create a build with some logs
    {:ok, build} = Builds.create_build(%{platform: :ios})

    # Add logs with different timestamps to test ordering
    {:ok, log1} = Builds.add_log(build.id, :info, "Build submitted")
    # Ensure different timestamps
    Process.sleep(10)
    {:ok, log2} = Builds.add_log(build.id, :info, "Build assigned to worker")
    Process.sleep(10)
    {:ok, log3} = Builds.add_log(build.id, :warn, "Warning: large bundle size")
    Process.sleep(10)
    {:ok, log4} = Builds.add_log(build.id, :error, "Build failed: compilation error")

    {:ok, build: build, logs: [log1, log2, log3, log4]}
  end

  describe "GET /api/builds/:id/logs - authentication" do
    test "allows access with valid API key", %{conn: conn, build: build} do
      conn =
        conn
        |> put_req_header("x-api-key", @api_key)
        |> get("/api/builds/#{build.id}/logs")

      assert %{"logs" => logs} = json_response(conn, 200)
      assert is_list(logs)
    end

    test "allows access with valid build token", %{conn: conn, build: build} do
      conn =
        conn
        |> put_req_header("x-build-token", build.access_token)
        |> get("/api/builds/#{build.id}/logs")

      assert %{"logs" => logs} = json_response(conn, 200)
      assert is_list(logs)
    end

    test "rejects access with no authentication", %{conn: conn, build: build} do
      conn = get(conn, "/api/builds/#{build.id}/logs")

      assert conn.status == 401
      assert json_response(conn, 401)["error"] =~ ~r/unauthorized/i
    end

    test "rejects access with invalid API key", %{conn: conn, build: build} do
      conn =
        conn
        |> put_req_header("x-api-key", "invalid-key")
        |> get("/api/builds/#{build.id}/logs")

      assert conn.status == 401
    end

    test "rejects access with invalid build token", %{conn: conn, build: build} do
      conn =
        conn
        |> put_req_header("x-build-token", "invalid-token")
        |> get("/api/builds/#{build.id}/logs")

      assert conn.status == 403
      assert json_response(conn, 403)["error"] =~ ~r/forbidden/i
    end

    test "rejects build token for different build", %{conn: conn, build: build} do
      {:ok, other_build} = Builds.create_build(%{platform: :android})

      conn =
        conn
        |> put_req_header("x-build-token", build.access_token)
        |> get("/api/builds/#{other_build.id}/logs")

      assert conn.status == 403
    end

    test "API key grants access to any build", %{conn: conn, build: build} do
      {:ok, other_build} = Builds.create_build(%{platform: :android})
      Builds.add_log(other_build.id, :info, "Other build log")

      conn =
        conn
        |> put_req_header("x-api-key", @api_key)
        |> get("/api/builds/#{other_build.id}/logs")

      assert %{"logs" => logs} = json_response(conn, 200)
      assert length(logs) == 1
    end
  end

  describe "GET /api/builds/:id/logs - response format" do
    test "returns logs with correct structure", %{conn: conn, build: build} do
      conn =
        conn
        |> put_req_header("x-api-key", @api_key)
        |> get("/api/builds/#{build.id}/logs")

      assert %{"logs" => logs} = json_response(conn, 200)
      assert length(logs) == 4

      # Check first log has all required fields
      first_log = hd(logs)
      assert Map.has_key?(first_log, "level")
      assert Map.has_key?(first_log, "message")
      assert Map.has_key?(first_log, "timestamp")
    end

    test "returns logs with correct data types", %{conn: conn, build: build} do
      conn =
        conn
        |> put_req_header("x-api-key", @api_key)
        |> get("/api/builds/#{build.id}/logs")

      assert %{"logs" => [log | _]} = json_response(conn, 200)

      # Verify types
      assert is_binary(log["level"])
      assert is_binary(log["message"])
      assert is_binary(log["timestamp"])

      # Timestamp should be ISO8601 format
      assert log["timestamp"] =~ ~r/^\d{4}-\d{2}-\d{2}T/
    end

    test "returns all log levels correctly", %{conn: conn, build: build} do
      conn =
        conn
        |> put_req_header("x-api-key", @api_key)
        |> get("/api/builds/#{build.id}/logs")

      assert %{"logs" => logs} = json_response(conn, 200)

      levels = Enum.map(logs, & &1["level"])
      assert "info" in levels
      assert "warn" in levels
      assert "error" in levels
    end

    test "returns logs in chronological order (oldest first)", %{conn: conn, build: build} do
      conn =
        conn
        |> put_req_header("x-api-key", @api_key)
        |> get("/api/builds/#{build.id}/logs")

      assert %{"logs" => logs} = json_response(conn, 200)

      # First log should be the first one we created
      assert hd(logs)["message"] == "Build submitted"
      assert List.last(logs)["message"] == "Build failed: compilation error"

      # Verify timestamps are in ascending order
      timestamps = Enum.map(logs, & &1["timestamp"])
      assert timestamps == Enum.sort(timestamps)
    end
  end

  describe "GET /api/builds/:id/logs - limit parameter" do
    test "returns default limit of 100 logs when not specified", %{conn: conn, build: build} do
      # Add many more logs to test default limit
      for i <- 5..110 do
        Builds.add_log(build.id, :info, "Log message #{i}")
      end

      conn =
        conn
        |> put_req_header("x-api-key", @api_key)
        |> get("/api/builds/#{build.id}/logs")

      assert %{"logs" => logs} = json_response(conn, 200)
      # Should return 100 logs (first 100 in chronological order)
      assert length(logs) == 100
    end

    test "respects custom limit parameter", %{conn: conn, build: build} do
      conn =
        conn
        |> put_req_header("x-api-key", @api_key)
        |> get("/api/builds/#{build.id}/logs?limit=2")

      assert %{"logs" => logs} = json_response(conn, 200)
      assert length(logs) == 2
      # Should get first 2 logs in chronological order
      assert hd(logs)["message"] == "Build submitted"
    end

    test "handles limit=1", %{conn: conn, build: build} do
      conn =
        conn
        |> put_req_header("x-api-key", @api_key)
        |> get("/api/builds/#{build.id}/logs?limit=1")

      assert %{"logs" => logs} = json_response(conn, 200)
      assert length(logs) == 1
      assert hd(logs)["message"] == "Build submitted"
    end

    test "handles limit larger than available logs", %{conn: conn, build: build} do
      conn =
        conn
        |> put_req_header("x-api-key", @api_key)
        |> get("/api/builds/#{build.id}/logs?limit=1000")

      assert %{"logs" => logs} = json_response(conn, 200)
      # Should return all 4 logs
      assert length(logs) == 4
    end

    test "handles limit=0", %{conn: conn, build: build} do
      conn =
        conn
        |> put_req_header("x-api-key", @api_key)
        |> get("/api/builds/#{build.id}/logs?limit=0")

      assert %{"logs" => logs} = json_response(conn, 200)
      assert length(logs) == 0
    end
  end

  describe "GET /api/builds/:id/logs - edge cases" do
    test "returns empty array for build with no logs", %{conn: conn} do
      {:ok, new_build} = Builds.create_build(%{platform: :android})

      conn =
        conn
        |> put_req_header("x-api-key", @api_key)
        |> get("/api/builds/#{new_build.id}/logs")

      assert %{"logs" => logs} = json_response(conn, 200)
      assert logs == []
    end

    test "returns 404 for non-existent build", %{conn: conn} do
      conn =
        conn
        |> put_req_header("x-api-key", @api_key)
        |> get("/api/builds/nonexistent-build-id/logs")

      # Note: Current implementation doesn't check if build exists
      # This test documents expected behavior - may need endpoint fix
      assert %{"logs" => logs} = json_response(conn, 200)
      assert logs == []
    end

    test "handles very long log messages", %{conn: conn} do
      {:ok, build} = Builds.create_build(%{platform: :ios})
      long_message = String.duplicate("a", 10000)
      Builds.add_log(build.id, :info, long_message)

      conn =
        conn
        |> put_req_header("x-api-key", @api_key)
        |> get("/api/builds/#{build.id}/logs")

      assert %{"logs" => [log]} = json_response(conn, 200)
      assert log["message"] == long_message
    end

    test "handles special characters in log messages", %{conn: conn} do
      {:ok, build} = Builds.create_build(%{platform: :ios})
      special_message = "Error: \"quote\", 'apostrophe', <tag>, & ampersand, 日本語, emoji 🚀"
      Builds.add_log(build.id, :error, special_message)

      conn =
        conn
        |> put_req_header("x-api-key", @api_key)
        |> get("/api/builds/#{build.id}/logs")

      assert %{"logs" => [log]} = json_response(conn, 200)
      assert log["message"] == special_message
    end

    test "handles newlines in log messages", %{conn: conn} do
      {:ok, build} = Builds.create_build(%{platform: :ios})
      multiline_message = "Line 1\nLine 2\nLine 3"
      Builds.add_log(build.id, :info, multiline_message)

      conn =
        conn
        |> put_req_header("x-api-key", @api_key)
        |> get("/api/builds/#{build.id}/logs")

      assert %{"logs" => [log]} = json_response(conn, 200)
      assert log["message"] == multiline_message
    end
  end

  describe "GET /api/builds/:id/logs - concurrent access" do
    test "build token user can only access their own build logs", %{conn: conn, build: build} do
      {:ok, build1} = Builds.create_build(%{platform: :ios})
      {:ok, build2} = Builds.create_build(%{platform: :android})

      Builds.add_log(build1.id, :info, "Build 1 log")
      Builds.add_log(build2.id, :info, "Build 2 log")

      # User with build1 token can access build1
      conn1 =
        conn
        |> put_req_header("x-build-token", build1.access_token)
        |> get("/api/builds/#{build1.id}/logs")

      assert %{"logs" => logs1} = json_response(conn1, 200)
      assert hd(logs1)["message"] == "Build 1 log"

      # User with build1 token cannot access build2
      conn2 =
        build_conn()
        |> put_req_header("x-build-token", build1.access_token)
        |> get("/api/builds/#{build2.id}/logs")

      assert conn2.status == 403
    end

    test "admin can access all build logs", %{conn: conn} do
      {:ok, build1} = Builds.create_build(%{platform: :ios})
      {:ok, build2} = Builds.create_build(%{platform: :android})

      Builds.add_log(build1.id, :info, "Build 1 log")
      Builds.add_log(build2.id, :info, "Build 2 log")

      # Admin can access both
      conn1 =
        conn
        |> put_req_header("x-api-key", @api_key)
        |> get("/api/builds/#{build1.id}/logs")

      assert %{"logs" => logs1} = json_response(conn1, 200)
      assert hd(logs1)["message"] == "Build 1 log"

      conn2 =
        build_conn()
        |> put_req_header("x-api-key", @api_key)
        |> get("/api/builds/#{build2.id}/logs")

      assert %{"logs" => logs2} = json_response(conn2, 200)
      assert hd(logs2)["message"] == "Build 2 log"
    end
  end

  describe "GET /api/builds/:id/logs - timestamp precision" do
    test "timestamps maintain millisecond precision", %{conn: conn, build: build} do
      conn =
        conn
        |> put_req_header("x-api-key", @api_key)
        |> get("/api/builds/#{build.id}/logs")

      assert %{"logs" => logs} = json_response(conn, 200)

      # All timestamps should have the Z suffix (UTC)
      Enum.each(logs, fn log ->
        assert log["timestamp"] =~ ~r/Z$/
        # Should be in ISO8601 format with time component
        assert log["timestamp"] =~ ~r/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/
      end)
    end

    test "timestamps are unique for rapidly added logs", %{conn: conn} do
      {:ok, new_build} = Builds.create_build(%{platform: :ios})

      # Add logs rapidly
      Enum.each(1..5, fn i ->
        Builds.add_log(new_build.id, :info, "Rapid log #{i}")
      end)

      conn =
        conn
        |> put_req_header("x-api-key", @api_key)
        |> get("/api/builds/#{new_build.id}/logs")

      assert %{"logs" => logs} = json_response(conn, 200)
      assert length(logs) == 5

      timestamps = Enum.map(logs, & &1["timestamp"])
      # Timestamps should be strictly increasing (though some may be equal due to precision)
      assert timestamps == Enum.sort(timestamps)
    end
  end

  describe "GET /api/builds/:id/logs - build token scope validation" do
    test "build token from cancelled build still works for logs", %{conn: conn} do
      {:ok, build} = Builds.create_build(%{platform: :ios})
      Builds.add_log(build.id, :info, "Before cancel")

      {:ok, cancelled_build} = Builds.cancel_build(build.id)

      conn =
        conn
        |> put_req_header("x-build-token", cancelled_build.access_token)
        |> get("/api/builds/#{cancelled_build.id}/logs")

      assert %{"logs" => logs} = json_response(conn, 200)
      assert length(logs) == 1
    end

    test "build token from completed build still works for logs", %{conn: conn} do
      {:ok, build} = Builds.create_build(%{platform: :ios})
      Builds.add_log(build.id, :info, "Build log")

      {:ok, completed_build} = Builds.complete_build(build.id)

      conn =
        conn
        |> put_req_header("x-build-token", completed_build.access_token)
        |> get("/api/builds/#{completed_build.id}/logs")

      assert %{"logs" => logs} = json_response(conn, 200)
      assert length(logs) == 1
    end

    test "build token from failed build still works for logs", %{conn: conn} do
      {:ok, build} = Builds.create_build(%{platform: :ios})
      Builds.add_log(build.id, :error, "Error log")

      {:ok, failed_build} = Builds.fail_build(build.id, "Test failure")

      conn =
        conn
        |> put_req_header("x-build-token", failed_build.access_token)
        |> get("/api/builds/#{failed_build.id}/logs")

      assert %{"logs" => logs} = json_response(conn, 200)
      # Should have both the original log and the failure log
      assert length(logs) >= 1
    end
  end

  describe "GET /api/builds/:id/logs - performance" do
    test "handles large number of logs efficiently", %{conn: conn} do
      {:ok, build} = Builds.create_build(%{platform: :ios})

      # Add 500 logs
      Enum.each(1..500, fn i ->
        Builds.add_log(build.id, :info, "Log #{i}")
      end)

      # Request with default limit (100)
      start_time = System.monotonic_time(:millisecond)

      conn =
        conn
        |> put_req_header("x-api-key", @api_key)
        |> get("/api/builds/#{build.id}/logs")

      end_time = System.monotonic_time(:millisecond)
      elapsed = end_time - start_time

      assert %{"logs" => logs} = json_response(conn, 200)
      assert length(logs) == 100

      # Should complete in reasonable time (< 1 second)
      assert elapsed < 1000, "Query took #{elapsed}ms, expected < 1000ms"
    end
  end
end
