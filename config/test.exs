import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

config :dcomp, :environment, :test

# Sync tests clone local fixture repos into a throwaway dir; the syncer is started by tests.
config :dcomp,
  mirror_dir: Path.join(System.tmp_dir!(), "dcomp_test_mirrors"),
  uploads_path: Path.join(System.tmp_dir!(), "dcomp_test_uploads"),
  git_protocols: ["file"],
  start_syncer: false

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :dcomp, Dcomp.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "dcomp_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :dcomp, DcompWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "H8wacx5GDeYpCY0O6SnFVd+BzhCh54JRLCAVdeD2QfgkwsxPoW9Vp8QPfy+uaNDV",
  server: false

# In test we don't send emails
config :dcomp, Dcomp.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

config :mix_test_watch, clear: true

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
