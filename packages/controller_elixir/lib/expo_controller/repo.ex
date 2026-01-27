defmodule ExpoController.Repo do
  use Ecto.Repo,
    otp_app: :expo_controller,
    adapter: Ecto.Adapters.Postgres
end
