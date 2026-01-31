defmodule ExpoController.Repo.Migrations.AddOtpToBuilds do
  use Ecto.Migration

  def change do
    alter table(:builds) do
      add :otp, :string
      add :otp_expires_at, :utc_datetime
      add :vm_token, :string
      add :vm_token_expires_at, :utc_datetime
    end

    create index(:builds, [:otp])
  end
end
