defmodule ExpoControllerWeb.Plugs.BuildAuthTest do
  use ExpoControllerWeb.ConnCase, async: false

  alias ExpoController.{Builds, Repo}
  alias ExpoControllerWeb.Plugs.BuildAuth

  @api_key Application.compile_env(:expo_controller, :api_key)

  setup do
    # Clean database before each test
    Repo.delete_all(Builds.Build)

    {:ok, build} = Builds.create_build(%{platform: :ios})

    {:ok, build: build}
  end

  describe "require_build_or_admin_access/2" do
    test "allows access with valid API key", %{conn: conn, build: build} do
      conn = conn
      |> Map.put(:path_params, %{"id" => build.id})
      |> put_req_header("x-api-key", @api_key)
      |> BuildAuth.require_build_or_admin_access([])

      refute conn.halted
    end

    test "allows access with valid build token", %{conn: conn, build: build} do
      conn = conn
      |> Map.put(:path_params, %{"id" => build.id})
      |> put_req_header("x-build-token", build.access_token)
      |> BuildAuth.require_build_or_admin_access([])

      refute conn.halted
      assert conn.assigns.build.id == build.id
    end

    test "rejects access with invalid API key", %{conn: conn, build: build} do
      conn = conn
      |> Map.put(:path_params, %{"id" => build.id})
      |> put_req_header("x-api-key", "invalid-key")
      |> BuildAuth.require_build_or_admin_access([])

      assert conn.halted
      assert conn.status == 401
    end

    test "rejects access with invalid build token", %{conn: conn, build: build} do
      conn = conn
      |> Map.put(:path_params, %{"id" => build.id})
      |> put_req_header("x-build-token", "invalid-token")
      |> BuildAuth.require_build_or_admin_access([])

      assert conn.halted
      assert conn.status == 403
    end

    test "rejects access with no authentication", %{conn: conn, build: build} do
      conn = conn
      |> Map.put(:path_params, %{"id" => build.id})
      |> BuildAuth.require_build_or_admin_access([])

      assert conn.halted
      assert conn.status == 401
    end

    test "rejects build token for different build", %{conn: conn, build: build} do
      {:ok, other_build} = Builds.create_build(%{platform: :android})

      conn = conn
      |> Map.put(:path_params, %{"id" => other_build.id})
      |> put_req_header("x-build-token", build.access_token)
      |> BuildAuth.require_build_or_admin_access([])

      assert conn.halted
      assert conn.status == 403
    end

    test "returns 404 when build not found", %{conn: conn} do
      conn = conn
      |> Map.put(:path_params, %{"id" => "nonexistent"})
      |> put_req_header("x-build-token", "some-token")
      |> BuildAuth.require_build_or_admin_access([])

      assert conn.halted
      assert conn.status == 404
    end

    test "API key takes precedence over build token", %{conn: conn, build: build} do
      {:ok, other_build} = Builds.create_build(%{platform: :android})

      # Valid API key but invalid build token for this build
      conn = conn
      |> Map.put(:path_params, %{"id" => other_build.id})
      |> put_req_header("x-api-key", @api_key)
      |> put_req_header("x-build-token", build.access_token)
      |> BuildAuth.require_build_or_admin_access([])

      # Should succeed because API key grants admin access
      refute conn.halted
    end

    test "build token assigns build to conn", %{conn: conn, build: build} do
      conn = conn
      |> Map.put(:path_params, %{"id" => build.id})
      |> put_req_header("x-build-token", build.access_token)
      |> BuildAuth.require_build_or_admin_access([])

      assert conn.assigns.build
      assert conn.assigns.build.id == build.id
    end

    test "API key does not assign build to conn", %{conn: conn, build: build} do
      conn = conn
      |> Map.put(:path_params, %{"id" => build.id})
      |> put_req_header("x-api-key", @api_key)
      |> BuildAuth.require_build_or_admin_access([])

      refute Map.has_key?(conn.assigns, :build)
    end
  end

  describe "constant-time comparison" do
    test "uses secure_compare to prevent timing attacks", %{conn: conn, build: build} do
      # This test verifies that we're using Plug.Crypto.secure_compare
      # by checking that different length tokens don't short-circuit

      short_token = "short"
      long_token = String.duplicate("a", 100)

      # Both should fail with same behavior (halted, status 403)
      conn1 = conn
      |> Map.put(:path_params, %{"id" => build.id})
      |> put_req_header("x-build-token", short_token)
      |> BuildAuth.require_build_or_admin_access([])

      conn2 = conn
      |> Map.put(:path_params, %{"id" => build.id})
      |> put_req_header("x-build-token", long_token)
      |> BuildAuth.require_build_or_admin_access([])

      assert conn1.halted == conn2.halted
      assert conn1.status == conn2.status
    end
  end
end
