defmodule ExpoController.BuildsTest do
  use ExpoController.DataCase

  alias ExpoController.Builds

  describe "builds" do
    alias ExpoController.Builds.Build

    import ExpoController.BuildsFixtures

    @invalid_attrs %{id: nil, status: nil, source_path: nil, error_message: nil, last_heartbeat_at: nil, submitted_at: nil, platform: nil, certs_path: nil, result_path: nil}

    test "list_builds/0 returns all builds" do
      build = build_fixture()
      assert Builds.list_builds() == [build]
    end

    test "get_build!/1 returns the build with given id" do
      build = build_fixture()
      assert Builds.get_build!(build.id) == build
    end

    test "create_build/1 with valid data creates a build" do
      valid_attrs = %{id: "some id", status: "some status", source_path: "some source_path", error_message: "some error_message", last_heartbeat_at: ~U[2026-01-26 02:44:00Z], submitted_at: ~U[2026-01-26 02:44:00Z], platform: "some platform", certs_path: "some certs_path", result_path: "some result_path"}

      assert {:ok, %Build{} = build} = Builds.create_build(valid_attrs)
      assert build.id == "some id"
      assert build.status == "some status"
      assert build.source_path == "some source_path"
      assert build.error_message == "some error_message"
      assert build.last_heartbeat_at == ~U[2026-01-26 02:44:00Z]
      assert build.submitted_at == ~U[2026-01-26 02:44:00Z]
      assert build.platform == "some platform"
      assert build.certs_path == "some certs_path"
      assert build.result_path == "some result_path"
    end

    test "create_build/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Builds.create_build(@invalid_attrs)
    end

    test "update_build/2 with valid data updates the build" do
      build = build_fixture()
      update_attrs = %{id: "some updated id", status: "some updated status", source_path: "some updated source_path", error_message: "some updated error_message", last_heartbeat_at: ~U[2026-01-27 02:44:00Z], submitted_at: ~U[2026-01-27 02:44:00Z], platform: "some updated platform", certs_path: "some updated certs_path", result_path: "some updated result_path"}

      assert {:ok, %Build{} = build} = Builds.update_build(build, update_attrs)
      assert build.id == "some updated id"
      assert build.status == "some updated status"
      assert build.source_path == "some updated source_path"
      assert build.error_message == "some updated error_message"
      assert build.last_heartbeat_at == ~U[2026-01-27 02:44:00Z]
      assert build.submitted_at == ~U[2026-01-27 02:44:00Z]
      assert build.platform == "some updated platform"
      assert build.certs_path == "some updated certs_path"
      assert build.result_path == "some updated result_path"
    end

    test "update_build/2 with invalid data returns error changeset" do
      build = build_fixture()
      assert {:error, %Ecto.Changeset{}} = Builds.update_build(build, @invalid_attrs)
      assert build == Builds.get_build!(build.id)
    end

    test "delete_build/1 deletes the build" do
      build = build_fixture()
      assert {:ok, %Build{}} = Builds.delete_build(build)
      assert_raise Ecto.NoResultsError, fn -> Builds.get_build!(build.id) end
    end

    test "change_build/1 returns a build changeset" do
      build = build_fixture()
      assert %Ecto.Changeset{} = Builds.change_build(build)
    end

    test "record_heartbeat/1 transitions assigned to building" do
      build = build_fixture(%{status: :assigned, last_heartbeat_at: nil})

      assert {:ok, updated} = Builds.record_heartbeat(build.id)
      assert updated.status == :building
      refute is_nil(updated.last_heartbeat_at)
    end
  end
end
