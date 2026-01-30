defmodule ExpoController.Repo.Migrations.CreateCpuSnapshots do
  use Ecto.Migration

  def change do
    create table(:cpu_snapshots, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :build_id, references(:builds, type: :string, on_delete: :delete_all), null: false
      add :timestamp, :utc_datetime, null: false
      add :cpu_percent, :float, null: false
      add :memory_mb, :float, null: false
    end

    create index(:cpu_snapshots, [:build_id])
    create index(:cpu_snapshots, [:timestamp])
  end
end
