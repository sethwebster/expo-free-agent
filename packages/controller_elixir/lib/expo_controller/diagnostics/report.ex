defmodule ExpoController.Diagnostics.Report do
  @moduledoc """
  Represents a diagnostic report from a worker.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :string

  schema "diagnostic_reports" do
    field :type, :string
    field :data, :map
    field :reported_at, :utc_datetime

    belongs_to :worker, ExpoController.Workers.Worker, type: :string

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def changeset(report, attrs) do
    report
    |> cast(attrs, [:type, :data, :worker_id, :reported_at])
    |> validate_required([:type, :data, :worker_id])
    |> foreign_key_constraint(:worker_id)
  end

  @doc """
  Changeset for creating a new diagnostic report.
  """
  def create_changeset(worker_id, type, data) do
    %__MODULE__{}
    |> changeset(%{
      worker_id: worker_id,
      type: type,
      data: data,
      reported_at: DateTime.utc_now()
    })
  end
end
