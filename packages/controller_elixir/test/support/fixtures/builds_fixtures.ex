defmodule ExpoController.BuildsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `ExpoController.Builds` context.
  """

  @doc """
  Generate a unique build id.
  """
  def unique_build_id, do: "some id#{System.unique_integer([:positive])}"

  @doc """
  Generate a build.
  """
  def build_fixture(attrs \\ %{}) do
    {:ok, build} =
      attrs
      |> Enum.into(%{
        certs_path: "some certs_path",
        error_message: "some error_message",
        id: unique_build_id(),
        last_heartbeat_at: ~U[2026-01-26 02:44:00Z],
        platform: "some platform",
        result_path: "some result_path",
        source_path: "some source_path",
        status: "some status",
        submitted_at: ~U[2026-01-26 02:44:00Z]
      })
      |> ExpoController.Builds.create_build()

    build
  end
end
