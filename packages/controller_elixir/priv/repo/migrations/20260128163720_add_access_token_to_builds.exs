defmodule ExpoController.Repo.Migrations.AddAccessTokenToBuilds do
  use Ecto.Migration

  def change do
    # Enable pgcrypto extension for gen_random_bytes
    execute "CREATE EXTENSION IF NOT EXISTS pgcrypto", "DROP EXTENSION IF EXISTS pgcrypto"

    alter table(:builds) do
      add :access_token, :string
    end

    # Generate access tokens for existing builds (migration safety)
    execute """
      UPDATE builds
      SET access_token = encode(gen_random_bytes(32), 'base64')
      WHERE access_token IS NULL
    """, ""

    # Make it non-null after backfilling
    alter table(:builds) do
      modify :access_token, :string, null: false
    end

    create index(:builds, [:access_token])
  end
end
