defmodule ExpoController.Builds.CpuSnapshot do
  @moduledoc """
  Represents a CPU and memory usage snapshot from a build VM.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :string

  schema "cpu_snapshots" do
    field :timestamp, :utc_datetime
    field :cpu_percent, :float
    field :memory_mb, :float

    belongs_to :build, ExpoController.Builds.Build, type: :string
  end

  @doc false
  def changeset(cpu_snapshot, attrs) do
    cpu_snapshot
    |> cast(attrs, [:build_id, :timestamp, :cpu_percent, :memory_mb])
    |> validate_required([:build_id, :timestamp, :cpu_percent, :memory_mb])
    |> validate_number(:cpu_percent, greater_than_or_equal_to: 0, less_than_or_equal_to: 1000)
    |> validate_number(:memory_mb, greater_than_or_equal_to: 0, less_than_or_equal_to: 1_000_000)
  end

  @doc """
  Creates a changeset for a new CPU snapshot.
  """
  def create_changeset(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
  end
end
