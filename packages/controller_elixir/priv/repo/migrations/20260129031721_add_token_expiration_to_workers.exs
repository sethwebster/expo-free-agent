defmodule ExpoController.Repo.Migrations.AddTokenExpirationToWorkers do
  use Ecto.Migration

  def change do
    alter table(:workers) do
      add :access_token_expires_at, :utc_datetime
    end
  end
end
