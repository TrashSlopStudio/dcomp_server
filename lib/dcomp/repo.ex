defmodule Dcomp.Repo do
  use Ecto.Repo,
    otp_app: :dcomp,
    adapter: Ecto.Adapters.Postgres
end
