defmodule ExpoController.Repo.Migrations.CreateWorkers do
  use Ecto.Migration

  def change do
    # Create workers table first (no foreign keys)
    create table(:workers, primary_key: false) do
      add :id, :string, primary_key: true
      add :name, :string, null: false
      add :status, :string, null: false, default: "idle"
      add :capabilities, :map, default: %{}
      add :builds_completed, :integer, default: 0
      add :builds_failed, :integer, default: 0
      add :last_seen_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    # Create builds table with foreign key to workers
    create table(:builds, primary_key: false) do
      add :id, :string, primary_key: true
      add :platform, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :source_path, :string
      add :certs_path, :string
      add :result_path, :string
      add :error_message, :text
      add :worker_id, references(:workers, type: :string, on_delete: :nilify_all)
      add :last_heartbeat_at, :utc_datetime
      add :submitted_at, :utc_datetime, null: false
      add :updated_at, :utc_datetime, null: false
    end

    create index(:builds, [:worker_id])
    create index(:builds, [:status])
    create index(:builds, [:status, :submitted_at])

    # Create build_logs table
    create table(:build_logs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :build_id, references(:builds, type: :string, on_delete: :delete_all), null: false
      add :level, :string, null: false
      add :message, :text, null: false
      add :timestamp, :utc_datetime, null: false
      add :inserted_at, :utc_datetime, null: false
    end

    create index(:build_logs, [:build_id])
    create index(:build_logs, [:build_id, :timestamp])

    # Create diagnostic_reports table
    create table(:diagnostic_reports, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :worker_id, references(:workers, type: :string, on_delete: :delete_all), null: false
      add :type, :string, null: false
      add :data, :map, null: false
      add :reported_at, :utc_datetime, null: false
      add :inserted_at, :utc_datetime, null: false
    end

    create index(:diagnostic_reports, [:worker_id])
    create index(:diagnostic_reports, [:reported_at])
  end
end
