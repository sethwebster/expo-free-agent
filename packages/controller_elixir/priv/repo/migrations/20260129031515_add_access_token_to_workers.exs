defmodule ExpoController.Repo.Migrations.AddAccessTokenToWorkers do
  use Ecto.Migration

  def change do
    alter table(:workers) do
      add :access_token, :string
    end

    create unique_index(:workers, [:access_token])
  end
end
