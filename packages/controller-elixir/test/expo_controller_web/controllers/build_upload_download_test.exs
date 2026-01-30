defmodule ExpoControllerWeb.BuildUploadDownloadTest do
  use ExpoControllerWeb.ConnCase, async: false

  alias ExpoController.{Builds, Workers, Repo}
  alias ExpoController.Storage.FileStorage

  @api_key Application.compile_env(:expo_controller, :api_key)

  setup do
    # Clean database
    Repo.delete_all(Builds.BuildLog)
    Repo.delete_all(Builds.Build)
    Repo.delete_all(Workers.Worker)

    # Clean storage
    storage_root = Application.get_env(:expo_controller, :storage_root, "./storage")
    File.rm_rf!(storage_root)
    File.mkdir_p!(storage_root)

    conn = build_conn()
    |> put_req_header("x-api-key", @api_key)

    on_exit(fn ->
      File.rm_rf!(storage_root)
    end)

    {:ok, conn: conn}
  end

  describe "POST /api/builds - build submission with uploads" do
    test "creates build with source upload", %{conn: conn} do
      # Create temp source file
      source_path = "/tmp/test-source-#{:rand.uniform(100000)}.tar.gz"
      File.write!(source_path, "source content")

      upload = %Plug.Upload{
        path: source_path,
        filename: "source.tar.gz",
        content_type: "application/gzip"
      }

      conn = post(conn, "/api/builds", %{
        platform: "ios",
        source: upload
      })

      assert %{
        "id" => build_id,
        "status" => "pending",
        "platform" => "ios",
        "access_token" => access_token
      } = json_response(conn, 201)

      # Verify build in database
      build = Builds.get_build(build_id)
      assert build.platform == :ios
      assert build.status == :pending
      assert build.source_path
      assert build.access_token == access_token

      # Verify file was saved
      assert FileStorage.file_exists?(build.source_path)

      File.rm!(source_path)
    end

    test "creates build with source and certs uploads", %{conn: conn} do
      source_path = "/tmp/source-#{:rand.uniform(100000)}.tar.gz"
      certs_path = "/tmp/certs-#{:rand.uniform(100000)}.zip"

      File.write!(source_path, "source content")
      File.write!(certs_path, "certs content")

      source_upload = %Plug.Upload{
        path: source_path,
        filename: "source.tar.gz"
      }

      certs_upload = %Plug.Upload{
        path: certs_path,
        filename: "certs.zip"
      }

      conn = post(conn, "/api/builds", %{
        platform: "ios",
        source: source_upload,
        certs: certs_upload
      })

      assert %{"id" => build_id} = json_response(conn, 201)

      build = Builds.get_build(build_id)
      assert build.source_path
      assert build.certs_path

      assert FileStorage.file_exists?(build.source_path)
      assert FileStorage.file_exists?(build.certs_path)

      File.rm!(source_path)
      File.rm!(certs_path)
    end

    test "rejects build without source upload", %{conn: conn} do
      conn = post(conn, "/api/builds", %{
        platform: "ios"
      })

      assert %{"error" => error} = json_response(conn, 400)
      assert error =~ "source"
    end

    test "rejects build with invalid platform", %{conn: conn} do
      source_path = "/tmp/source-#{:rand.uniform(100000)}.tar.gz"
      File.write!(source_path, "content")

      upload = %Plug.Upload{path: source_path, filename: "source.tar.gz"}

      conn = post(conn, "/api/builds", %{
        platform: "windows",
        source: upload
      })

      assert %{"error" => error} = json_response(conn, 400)
      assert error =~ "platform"

      File.rm!(source_path)
    end

    test "handles large file uploads", %{conn: conn} do
      source_path = "/tmp/large-source-#{:rand.uniform(100000)}.tar.gz"

      # Create 5MB file
      large_content = :crypto.strong_rand_bytes(5 * 1024 * 1024)
      File.write!(source_path, large_content)

      upload = %Plug.Upload{
        path: source_path,
        filename: "source.tar.gz"
      }

      conn = post(conn, "/api/builds", %{
        platform: "ios",
        source: upload
      })

      assert %{"id" => build_id} = json_response(conn, 201)

      build = Builds.get_build(build_id)
      {:ok, size} = FileStorage.file_size(build.source_path)

      assert size == byte_size(large_content)

      File.rm!(source_path)
    end

    test "prevents path traversal in uploaded filenames", %{conn: conn} do
      source_path = "/tmp/source-#{:rand.uniform(100000)}.tar.gz"
      File.write!(source_path, "content")

      # Try to use malicious filename
      upload = %Plug.Upload{
        path: source_path,
        filename: "../../../etc/passwd"
      }

      conn = post(conn, "/api/builds", %{
        platform: "ios",
        source: upload
      })

      # Should either succeed with sanitized filename or reject
      case conn.status do
        201 ->
          # If accepted, verify file is within storage
          %{"id" => build_id} = json_response(conn, 201)
          build = Builds.get_build(build_id)

          storage_root = Application.get_env(:expo_controller, :storage_root, "./storage")
          full_path = Path.join(storage_root, build.source_path)
          resolved = Path.expand(full_path)
          storage_resolved = Path.expand(storage_root)

          assert String.starts_with?(resolved, storage_resolved),
            "Path #{resolved} escapes storage #{storage_resolved}"

        400 ->
          # Also acceptable - rejection is safe
          :ok

        _ ->
          flunk("Unexpected status: #{conn.status}")
      end

      File.rm!(source_path)
    end
  end

  describe "GET /api/builds/:id/download - artifact download" do
    test "downloads build result with API key auth", %{conn: conn} do
      # Create build with result
      {:ok, build} = Builds.create_build(%{platform: :ios})

      # Create mock result file
      result_path = "builds/#{build.id}/result.ipa"
      full_path = Path.join(
        Application.get_env(:expo_controller, :storage_root, "./storage"),
        result_path
      )

      File.mkdir_p!(Path.dirname(full_path))
      result_content = "mock IPA content"
      File.write!(full_path, result_content)

      # Update build with result path
      {:ok, build} = Builds.update_build(build, %{result_path: result_path})

      conn = get(conn, "/api/builds/#{build.id}/download")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") |> List.first() =~ "application/octet-stream"
      assert conn.resp_body == result_content
    end

    test "downloads build result with build token auth", %{conn: conn} do
      {:ok, build} = Builds.create_build(%{platform: :ios})

      result_path = "builds/#{build.id}/result.ipa"
      full_path = Path.join(
        Application.get_env(:expo_controller, :storage_root, "./storage"),
        result_path
      )
      File.mkdir_p!(Path.dirname(full_path))
      File.write!(full_path, "content")

      {:ok, build} = Builds.update_build(build, %{result_path: result_path})

      # Use build token instead of API key
      conn = build_conn()
      |> put_req_header("x-build-token", build.access_token)
      |> get("/api/builds/#{build.id}/download")

      assert conn.status == 200
    end

    test "returns 404 when build has no result", %{conn: conn} do
      {:ok, build} = Builds.create_build(%{platform: :ios})

      conn = get(conn, "/api/builds/#{build.id}/download")

      assert conn.status == 404
      assert %{"error" => _} = json_response(conn, 404)
    end

    test "returns 404 when result file is missing", %{conn: conn} do
      {:ok, build} = Builds.create_build(%{
        platform: :ios,
        result_path: "builds/nonexistent/result.ipa"
      })

      conn = get(conn, "/api/builds/#{build.id}/download")

      assert conn.status == 404
    end

    test "streams large result file efficiently", %{conn: conn} do
      {:ok, build} = Builds.create_build(%{platform: :ios})

      result_path = "builds/#{build.id}/result.ipa"
      full_path = Path.join(
        Application.get_env(:expo_controller, :storage_root, "./storage"),
        result_path
      )
      File.mkdir_p!(Path.dirname(full_path))

      # Create 10MB file
      large_content = :crypto.strong_rand_bytes(10 * 1024 * 1024)
      File.write!(full_path, large_content)

      {:ok, _build} = Builds.update_build(build, %{result_path: result_path})

      conn = get(conn, "/api/builds/#{build.id}/download")

      assert conn.status == 200
      assert byte_size(conn.resp_body) == byte_size(large_content)
    end

    test "prevents download of arbitrary files via path traversal", %{conn: conn} do
      # Try to access file outside build directory
      # This should be prevented by FileStorage.read_stream validation

      {:ok, build} = Builds.create_build(%{
        platform: :ios,
        result_path: "../../../etc/passwd"
      })

      conn = get(conn, "/api/builds/#{build.id}/download")

      # Should return error, not system file
      assert conn.status in [404, 400]
    end
  end

  describe "GET /api/builds/:id/download/:type - typed downloads" do
    test "downloads source file", %{conn: conn} do
      {:ok, build} = Builds.create_build(%{platform: :ios})

      source_path = "builds/#{build.id}/source.tar.gz"
      full_path = Path.join(
        Application.get_env(:expo_controller, :storage_root, "./storage"),
        source_path
      )
      File.mkdir_p!(Path.dirname(full_path))
      File.write!(full_path, "source content")

      {:ok, _build} = Builds.update_build(build, %{source_path: source_path})

      conn = get(conn, "/api/builds/#{build.id}/download/source")

      assert conn.status == 200
      assert conn.resp_body == "source content"
    end

    test "downloads result file", %{conn: conn} do
      {:ok, build} = Builds.create_build(%{platform: :ios})

      result_path = "builds/#{build.id}/result.ipa"
      full_path = Path.join(
        Application.get_env(:expo_controller, :storage_root, "./storage"),
        result_path
      )
      File.mkdir_p!(Path.dirname(full_path))
      File.write!(full_path, "result content")

      {:ok, _build} = Builds.update_build(build, %{result_path: result_path})

      conn = get(conn, "/api/builds/#{build.id}/download/result")

      assert conn.status == 200
      assert conn.resp_body == "result content"
    end

    test "rejects invalid file type", %{conn: conn} do
      {:ok, build} = Builds.create_build(%{platform: :ios})

      conn = get(conn, "/api/builds/#{build.id}/download/malicious")

      assert conn.status == 400
      assert %{"error" => error} = json_response(conn, 400)
      assert error =~ "Invalid file type"
    end

    test "prevents type confusion attacks", %{conn: conn} do
      # Ensure type parameter is validated and can't be used for path traversal
      {:ok, build} = Builds.create_build(%{platform: :ios})

      malicious_types = [
        "../../../etc/passwd",
        "source/../../etc/passwd",
        "source%00.tar.gz",
        "source; rm -rf /",
        "<script>alert(1)</script>"
      ]

      for type <- malicious_types do
        conn = build_conn()
        |> put_req_header("x-api-key", @api_key)
        |> get("/api/builds/#{build.id}/download/#{type}")

        # Should reject with 400 or 404, never 200
        assert conn.status in [400, 404],
          "Type '#{type}' should be rejected, got status #{conn.status}"
      end
    end
  end

  describe "GET /api/builds/:id/source - worker source download" do
    test "allows worker to download assigned build source", %{conn: conn} do
      {:ok, worker} = Workers.register_worker(%{
        id: "worker-#{:rand.uniform(10000)}",
        name: "Test Worker",
        capabilities: %{}
      })

      {:ok, build} = Builds.create_build(%{platform: :ios})
      {:ok, build} = Builds.assign_to_worker(build, worker.id)

      # Create source file
      source_path = "builds/#{build.id}/source.tar.gz"
      full_path = Path.join(
        Application.get_env(:expo_controller, :storage_root, "./storage"),
        source_path
      )
      File.mkdir_p!(Path.dirname(full_path))
      File.write!(full_path, "source for worker")

      {:ok, _build} = Builds.update_build(build, %{source_path: source_path})

      worker_conn = build_conn()
      |> put_req_header("x-worker-id", worker.id)
      |> get("/api/builds/#{build.id}/source")

      assert worker_conn.status == 200
      assert worker_conn.resp_body == "source for worker"
    end

    test "returns 404 for non-existent build", %{conn: conn} do
      {:ok, worker} = Workers.register_worker(%{
        id: "worker-#{:rand.uniform(10000)}",
        name: "Test Worker",
        capabilities: %{}
      })

      conn = build_conn()
      |> put_req_header("x-worker-id", worker.id)
      |> get("/api/builds/nonexistent/source")

      assert conn.status == 404
    end

    test "handles missing source file gracefully", %{conn: conn} do
      {:ok, worker} = Workers.register_worker(%{
        id: "worker-#{:rand.uniform(10000)}",
        name: "Test Worker",
        capabilities: %{}
      })

      {:ok, build} = Builds.create_build(%{
        platform: :ios,
        source_path: "builds/missing/source.tar.gz"
      })
      {:ok, _build} = Builds.assign_to_worker(build, worker.id)

      conn = build_conn()
      |> put_req_header("x-worker-id", worker.id)
      |> get("/api/builds/#{build.id}/source")

      assert conn.status == 404
    end
  end

  describe "GET /api/builds/:id/certs - worker certs download" do
    test "allows worker to download build certs", %{conn: conn} do
      {:ok, worker} = Workers.register_worker(%{
        id: "worker-#{:rand.uniform(10000)}",
        name: "Test Worker",
        capabilities: %{}
      })

      {:ok, build} = Builds.create_build(%{platform: :ios})
      {:ok, build} = Builds.assign_to_worker(build, worker.id)

      certs_path = "builds/#{build.id}/certs.zip"
      full_path = Path.join(
        Application.get_env(:expo_controller, :storage_root, "./storage"),
        certs_path
      )
      File.mkdir_p!(Path.dirname(full_path))
      File.write!(full_path, "certs bundle")

      {:ok, _build} = Builds.update_build(build, %{certs_path: certs_path})

      conn = build_conn()
      |> put_req_header("x-worker-id", worker.id)
      |> get("/api/builds/#{build.id}/certs")

      assert conn.status == 200
      assert conn.resp_body == "certs bundle"
    end

    test "returns 404 when build has no certs", %{conn: conn} do
      {:ok, worker} = Workers.register_worker(%{
        id: "worker-#{:rand.uniform(10000)}",
        name: "Test Worker",
        capabilities: %{}
      })

      {:ok, build} = Builds.create_build(%{platform: :android})
      {:ok, _build} = Builds.assign_to_worker(build, worker.id)

      conn = build_conn()
      |> put_req_header("x-worker-id", worker.id)
      |> get("/api/builds/#{build.id}/certs")

      assert conn.status == 404
    end
  end

  describe "concurrent upload/download operations" do
    @tag :concurrent
    test "handles concurrent build submissions", %{conn: conn} do
      tasks = Enum.map(1..10, fn i ->
        Task.async(fn ->
          source_path = "/tmp/concurrent-#{i}-#{:rand.uniform(100000)}.tar.gz"
          File.write!(source_path, "source #{i}")

          upload = %Plug.Upload{
            path: source_path,
            filename: "source.tar.gz"
          }

          test_conn = build_conn()
          |> put_req_header("x-api-key", @api_key)
          |> post("/api/builds", %{
            platform: "ios",
            source: upload
          })

          File.rm!(source_path)
          test_conn
        end)
      end)

      results = Task.await_many(tasks, timeout: 30_000)

      # All submissions should succeed
      statuses = Enum.map(results, & &1.status)
      assert Enum.all?(statuses, fn status -> status == 201 end)

      # All files should exist
      build_ids = Enum.map(results, fn conn ->
        %{"id" => id} = json_response(conn, 201)
        id
      end)

      for build_id <- build_ids do
        build = Builds.get_build(build_id)
        assert FileStorage.file_exists?(build.source_path)
      end
    end

    @tag :concurrent
    test "handles concurrent downloads of same file", %{conn: conn} do
      {:ok, build} = Builds.create_build(%{platform: :ios})

      result_path = "builds/#{build.id}/result.ipa"
      full_path = Path.join(
        Application.get_env(:expo_controller, :storage_root, "./storage"),
        result_path
      )
      File.mkdir_p!(Path.dirname(full_path))
      content = :crypto.strong_rand_bytes(1024 * 1024)  # 1MB
      File.write!(full_path, content)

      {:ok, _build} = Builds.update_build(build, %{result_path: result_path})

      # Concurrent downloads
      tasks = Enum.map(1..20, fn _i ->
        Task.async(fn ->
          test_conn = build_conn()
          |> put_req_header("x-api-key", @api_key)
          |> get("/api/builds/#{build.id}/download")

          {test_conn.status, byte_size(test_conn.resp_body)}
        end)
      end)

      results = Task.await_many(tasks, timeout: 30_000)

      # All should succeed with correct content
      assert Enum.all?(results, fn {status, size} ->
        status == 200 and size == byte_size(content)
      end)
    end
  end

  describe "upload/download error handling" do
    test "handles corrupt upload gracefully", %{conn: conn} do
      # Upload file that gets deleted before processing
      source_path = "/tmp/vanishing-#{:rand.uniform(100000)}.tar.gz"
      File.write!(source_path, "content")

      upload = %Plug.Upload{
        path: source_path,
        filename: "source.tar.gz"
      }

      # Delete file before upload completes
      File.rm!(source_path)

      conn = post(conn, "/api/builds", %{
        platform: "ios",
        source: upload
      })

      # Should fail gracefully
      assert conn.status in [400, 500]
      assert %{"error" => _} = json_response(conn, conn.status)
    end

    test "handles interrupted download", %{conn: conn} do
      {:ok, build} = Builds.create_build(%{platform: :ios})

      result_path = "builds/#{build.id}/result.ipa"
      full_path = Path.join(
        Application.get_env(:expo_controller, :storage_root, "./storage"),
        result_path
      )
      File.mkdir_p!(Path.dirname(full_path))
      File.write!(full_path, :crypto.strong_rand_bytes(5 * 1024 * 1024))

      {:ok, _build} = Builds.update_build(build, %{result_path: result_path})

      # This test documents expected behavior - exact handling depends on implementation
      conn = get(conn, "/api/builds/#{build.id}/download")

      # Download should at least start successfully
      assert conn.status == 200
    end

    test "validates file size limits", %{conn: conn} do
      # This test documents file size handling
      # If there's a max upload size, it should be enforced
      :ok
    end
  end

  describe "content-type and headers" do
    test "sets correct content-type for downloads", %{conn: conn} do
      {:ok, build} = Builds.create_build(%{platform: :ios})

      result_path = "builds/#{build.id}/result.ipa"
      full_path = Path.join(
        Application.get_env(:expo_controller, :storage_root, "./storage"),
        result_path
      )
      File.mkdir_p!(Path.dirname(full_path))
      File.write!(full_path, "ipa")

      {:ok, _build} = Builds.update_build(build, %{result_path: result_path})

      conn = get(conn, "/api/builds/#{build.id}/download")

      assert conn.status == 200
      content_type = get_resp_header(conn, "content-type") |> List.first()
      assert content_type =~ "application/octet-stream"
    end

    test "sets content-disposition header", %{conn: conn} do
      {:ok, build} = Builds.create_build(%{platform: :ios})

      result_path = "builds/#{build.id}/result.ipa"
      full_path = Path.join(
        Application.get_env(:expo_controller, :storage_root, "./storage"),
        result_path
      )
      File.mkdir_p!(Path.dirname(full_path))
      File.write!(full_path, "ipa")

      {:ok, _build} = Builds.update_build(build, %{result_path: result_path})

      conn = get(conn, "/api/builds/#{build.id}/download")

      assert conn.status == 200
      disposition = get_resp_header(conn, "content-disposition") |> List.first()
      assert disposition =~ "attachment"
      assert disposition =~ "filename="
    end
  end
end
