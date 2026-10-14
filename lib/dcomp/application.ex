defmodule Dcomp.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      DcompWeb.Telemetry,
      Dcomp.Repo,
      {Redix, host: redis_host(), name: :redix, password: redis_pass()},
      {DNSCluster, query: Application.get_env(:dcomp, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Dcomp.PubSub}
    ]

    children =
      children ++
        if(Application.get_env(:dcomp, :start_syncer), do: [Dcomp.Decomp.Syncer], else: []) ++
        [DcompWeb.Endpoint]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Dcomp.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    DcompWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  @spec env :: :dev | :test | :prod
  def env, do: Application.fetch_env!(:dcomp, :environment)

  @spec stage :: :local | :dev
  def stage, do: Application.fetch_env!(:dcomp, :stage)

  def redis_host, do: Application.fetch_env!(:dcomp, :redis_host)

  def redis_pass, do: Application.fetch_env!(:dcomp, :redis_pass)
end
