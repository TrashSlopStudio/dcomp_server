import Config

require Logger

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/dcomp start
if System.get_env("PHX_SERVER") do
  config :dcomp, DcompWeb.Endpoint,
    server: true,
    check_origin: false
end

config :dcomp, stage: System.fetch_env!("STAGE")

config :dcomp,
  redis_host: System.fetch_env!("REDIS_HOST"),
  redis_pass: System.fetch_env!("REDIS_PASS")

if config_env() == :dev do
  config :dcomp, DcompWeb.Endpoint,
    http: [port: String.to_integer(System.get_env("PORT", "4000"))],
    live_reload: [
      web_console_logger: true,
      patterns: [
        ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$"E,
        ~r"priv/gettext/.*\.po$"E,
        ~r"lib/dcomp_web/router\.ex$"E,
        ~r"lib/dcomp_web/(controllers|live|components)/.*\.(ex|heex)$"E
      ]
    ]
end

if config_env() == :prod do
  maybe_ipv6 =
    if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :dcomp, Dcomp.Repo,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6

  host = System.fetch_env!("APP_HOST")
  port = String.to_integer(System.get_env("PORT", "443"))

  case System.get_env("STAGE") do
    stage when stage in ["local", "dev", "staging", "prod"] ->
      :ok =
        Logger.warning(
          "Ignoring variable DATABASE_URL as Postgrex connection protocol, proceding with default tcp connection."
        )

      config(:dcomp, Dcomp.Repo,
        database: System.get_env("DB_DATABASE"),
        username: System.fetch_env!("DB_USERNAME"),
        password: System.fetch_env!("DB_PASSWORD"),
        hostname: System.fetch_env!("DB_HOSTNAME")
      )

      config :dcomp, DcompWeb.Endpoint,
        http: [
          port: port,
          transport_options: [socket_opts: [:inet6]]
        ],
        url: [host: host, port: 80]

    _stage ->
      database_url =
        System.get_env("DATABASE_URL") ||
          raise """
          environment variable DATABASE_URL is missing.
          For example: ecto://USER:PASS@HOST/DATABASE
          """

      :ok = Logger.info("Using DATABASE_URL as Postgrex connection protocol.")

      config :dcomp, Dcomp.Repo,
        ssl: true,
        url: database_url,
        database: Enum.at(String.split(database_url, "/"), -1)

      config :dcomp, DcompWeb.Endpoint,
        http: [
          # Enable IPv6 and bind on all interfaces.
          ip: {0, 0, 0, 0, 0, 0, 0, 0},
          port: port
        ],
        url: [scheme: "https", host: host, port: port]
  end

  # The secret key base is used to sign/encrypt cookies and other secrets.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  config :dcomp, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")
  config :dcomp, DcompWeb.Endpoint, secret_key_base: secret_key_base

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end
