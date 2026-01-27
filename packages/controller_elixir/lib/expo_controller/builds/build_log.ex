defmodule ExpoController.Builds.BuildLog do
  @moduledoc """
  Represents a log entry for a build.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :string

  schema "build_logs" do
    field :level, Ecto.Enum, values: [:info, :warn, :error]
    field :message, :string
    field :timestamp, :utc_datetime

    belongs_to :build, ExpoController.Builds.Build, type: :string

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def changeset(log, attrs) do
    log
    |> cast(attrs, [:level, :message, :timestamp, :build_id])
    |> validate_required([:level, :message, :build_id])
    |> validate_inclusion(:level, [:info, :warn, :error])
    |> foreign_key_constraint(:build_id)
  end

  @doc """
  Changeset for creating a new log entry.
  """
  def create_changeset(build_id, level, message) do
    %__MODULE__{}
    |> changeset(%{
      build_id: build_id,
      level: level,
      message: message,
      timestamp: DateTime.utc_now()
    })
  end
end
