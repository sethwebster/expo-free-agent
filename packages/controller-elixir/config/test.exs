import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :expo_controller, ExpoController.Repo,
  username: "expo",
  password: "expo_dev",
  hostname: "localhost",
  database: "expo_controller_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# Test API key (must be at least 32 characters)
config :expo_controller, :api_key, "test-api-key-for-testing-purposes-only-32-chars-minimum"

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :expo_controller, ExpoControllerWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "ohfOACww1TOinLKems1dCEgQK+2xcZMc85Yu+Ojwj+LjQbWBE0HrMa/Ght3bsa1j",
  server: false

# In test we don't send emails
config :expo_controller, ExpoController.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# Configure storage path for build artifacts (tests override per-test)
config :expo_controller, :storage_path, "./test_storage"
