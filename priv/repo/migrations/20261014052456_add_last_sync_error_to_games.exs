defmodule Dcomp.Repo.Migrations.AddLastSyncErrorToGames do
  use Ecto.Migration

  def change do
    alter table(:games) do
      add :last_sync_error, :text
    end
  end
end
