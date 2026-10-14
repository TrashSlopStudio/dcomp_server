defmodule Dcomp.Repo.Migrations.SettingsSingleton do
  use Ecto.Migration

  # An index on a constant allows at most one row.
  def change do
    create unique_index(:settings, ["(true)"], name: :settings_singleton)
  end
end
