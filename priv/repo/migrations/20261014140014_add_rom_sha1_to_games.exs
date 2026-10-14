defmodule Dcomp.Repo.Migrations.AddRomSha1ToGames do
  use Ecto.Migration

  def change do
    alter table(:games) do
      add :rom_sha1, :string
    end
  end
end
