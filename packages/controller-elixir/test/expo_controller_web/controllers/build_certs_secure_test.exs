defmodule ExpoControllerWeb.BuildCertsSecureTest do
  use ExpoControllerWeb.ConnCase, async: false

  alias ExpoController.{Builds, Repo}

  setup do
    Repo.delete_all(Builds.Build)

    storage_root = Path.join(System.tmp_dir!(), "expo-free-agent-certs-#{System.unique_integer([:positive])}")
    previous_storage_root = Application.get_env(:expo_controller, :storage_root)
    Application.put_env(:expo_controller, :storage_root, storage_root)
    File.mkdir_p!(storage_root)

    on_exit(fn ->
      if previous_storage_root do
        Application.put_env(:expo_controller, :storage_root, previous_storage_root)
      else
        Application.delete_env(:expo_controller, :storage_root)
      end

      File.rm_rf!(storage_root)
    end)

    build_id = "build-#{System.unique_integer([:positive])}"
    vm_token = "vm-token-#{System.unique_integer([:positive])}"
    vm_token_expires_at = DateTime.add(DateTime.utc_now(), 3600, :second) |> DateTime.truncate(:second)

    {:ok, build} = Builds.create_build(%{
      id: build_id,
      platform: :ios,
      certs_path: "builds/#{build_id}/certs.zip",
      vm_token: vm_token,
      vm_token_expires_at: vm_token_expires_at
    })

    conn = build_conn()
    |> put_req_header("x-vm-token", vm_token)

    {:ok, conn: conn, build: build, storage_root: storage_root}
  end

  test "returns certs when zip is valid", %{conn: conn, build: build, storage_root: storage_root} do
    certs_path = Path.join(storage_root, build.certs_path)
    File.mkdir_p!(Path.dirname(certs_path))

    :ok = create_certs_zip(certs_path, [
      {~c"cert.p12", "mock p12"},
      {~c"password.txt", "test_password"},
      {~c"profile.mobileprovision", "mock profile"}
    ])

    conn = get(conn, "/api/builds/#{build.id}/certs-secure")

    assert conn.status == 200
    response = json_response(conn, 200)
    assert is_binary(response["p12"])
    assert response["p12Password"] == "test_password"
    assert is_binary(response["keychainPassword"])
    assert is_list(response["provisioningProfiles"])
    assert length(response["provisioningProfiles"]) == 1
  end

  test "rejects oversized certs bundle", %{conn: conn, build: build, storage_root: storage_root} do
    certs_path = Path.join(storage_root, build.certs_path)
    File.mkdir_p!(Path.dirname(certs_path))

    previous_limit = Application.get_env(:expo_controller, :max_certs_zip_bytes)
    Application.put_env(:expo_controller, :max_certs_zip_bytes, 32)

    on_exit(fn ->
      if previous_limit do
        Application.put_env(:expo_controller, :max_certs_zip_bytes, previous_limit)
      else
        Application.delete_env(:expo_controller, :max_certs_zip_bytes)
      end
    end)

    :ok = create_certs_zip(certs_path, [
      {~c"cert.p12", String.duplicate("a", 128)},
      {~c"password.txt", "test_password"}
    ])

    conn = get(conn, "/api/builds/#{build.id}/certs-secure")

    assert conn.status == 413
    assert json_response(conn, 413)["error"] =~ "Certs bundle too large"
  end

  defp create_certs_zip(path, entries) do
    tmp_dir = Path.join(System.tmp_dir!(), "expo-certs-zip-#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp_dir)

    try do
      Enum.each(entries, fn {name, data} ->
        File.write!(Path.join(tmp_dir, List.to_string(name)), data)
      end)

      file_names = Enum.map(entries, fn {name, _} -> List.to_string(name) end)
      args = ["-q", "-r", path] ++ file_names
      {_, status} = System.cmd("zip", args, cd: tmp_dir)

      if status != 0 do
        flunk("Failed to create zip: zip exit #{status}")
      end

      case :zip.unzip(to_charlist(path), [:memory]) do
        {:ok, _} -> :ok
        {:error, reason} -> flunk("Generated zip failed to unzip: #{inspect(reason)}")
      end
    after
      File.rm_rf!(tmp_dir)
    end
  end
end
