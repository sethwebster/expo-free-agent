defmodule ExpoController.Builds.Build do
  @moduledoc """
  Represents a build submission in the system.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string

  schema "builds" do
    field :platform, Ecto.Enum, values: [:ios, :android]
    field :status, Ecto.Enum,
      values: [:pending, :assigned, :building, :completed, :failed, :cancelled]
    field :source_path, :string
    field :certs_path, :string
    field :result_path, :string
    field :error_message, :string
    field :last_heartbeat_at, :utc_datetime

    belongs_to :worker, ExpoController.Workers.Worker, type: :string, foreign_key: :worker_id
    has_many :logs, ExpoController.Builds.BuildLog

    timestamps(type: :utc_datetime, inserted_at: :submitted_at)
  end

  @doc false
  def changeset(build, attrs) do
    build
    |> cast(attrs, [
      :id,
      :platform,
      :status,
      :source_path,
      :certs_path,
      :result_path,
      :error_message,
      :worker_id,
      :last_heartbeat_at
    ])
    |> validate_required([:id, :platform, :status])
    |> validate_inclusion(:platform, [:ios, :android])
    |> validate_inclusion(:status, [:pending, :assigned, :building, :completed, :failed, :cancelled])
    |> unique_constraint(:id, name: :builds_pkey)
  end

  @doc """
  Changeset for creating a new build.
  """
  def create_changeset(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> put_change(:status, :pending)
    |> validate_required([:id, :platform])
  end

  @doc """
  Changeset for assigning a build to a worker.
  """
  def assign_changeset(build, worker_id) do
    build
    |> change(status: :assigned, worker_id: worker_id)
    |> validate_required([:worker_id])
  end

  @doc """
  Changeset for updating heartbeat.
  """
  def heartbeat_changeset(build) do
    change(build, last_heartbeat_at: DateTime.utc_now())
  end

  @doc """
  Changeset for completing a build.
  """
  def complete_changeset(build, result_path) do
    build
    |> change(status: :completed, result_path: result_path)
    |> validate_required([:result_path])
  end

  @doc """
  Changeset for failing a build.
  """
  def fail_changeset(build, error_message) do
    build
    |> change(status: :failed, error_message: error_message)
    |> validate_required([:error_message])
  end
end
