defmodule ExpoController.Workers.Worker do
  @moduledoc """
  Represents a worker machine that executes builds.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string

  schema "workers" do
    field :name, :string
    field :status, Ecto.Enum, values: [:idle, :building, :offline]
    field :capabilities, :map
    field :builds_completed, :integer, default: 0
    field :builds_failed, :integer, default: 0
    field :last_seen_at, :utc_datetime

    has_many :builds, ExpoController.Builds.Build
    has_many :diagnostics, ExpoController.Diagnostics.Report

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(worker, attrs) do
    worker
    |> cast(attrs, [
      :id,
      :name,
      :status,
      :capabilities,
      :builds_completed,
      :builds_failed,
      :last_seen_at
    ])
    |> validate_required([:id, :name])
    |> validate_inclusion(:status, [:idle, :building, :offline])
    |> unique_constraint(:id, name: :workers_pkey)
  end

  @doc """
  Changeset for worker registration.
  """
  def registration_changeset(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> put_change(:status, :idle)
    |> put_change(:last_seen_at, DateTime.utc_now() |> DateTime.truncate(:second))
    |> validate_required([:id, :name, :status, :last_seen_at])
  end

  @doc """
  Changeset for updating last seen timestamp.
  """
  def heartbeat_changeset(worker) do
    change(worker, last_seen_at: DateTime.utc_now() |> DateTime.truncate(:second))
  end

  @doc """
  Changeset for marking worker as building.
  """
  def building_changeset(worker) do
    change(worker, status: :building, last_seen_at: DateTime.utc_now() |> DateTime.truncate(:second))
  end

  @doc """
  Changeset for marking worker as idle.
  """
  def idle_changeset(worker) do
    change(worker, status: :idle, last_seen_at: DateTime.utc_now() |> DateTime.truncate(:second))
  end

  @doc """
  Changeset for incrementing completed builds counter.
  """
  def increment_completed_changeset(worker) do
    change(worker, builds_completed: worker.builds_completed + 1)
  end

  @doc """
  Changeset for incrementing failed builds counter.
  """
  def increment_failed_changeset(worker) do
    change(worker, builds_failed: worker.builds_failed + 1)
  end
end
