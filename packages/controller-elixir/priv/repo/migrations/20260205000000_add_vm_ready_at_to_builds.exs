defmodule ExpoController.Repo.Migrations.AddVmReadyAtToBuilds do
  use Ecto.Migration

  def change do
    alter table(:builds) do
      add :vm_ready_at, :utc_datetime
    end

    create index(:builds, [:vm_ready_at])
  end
end
