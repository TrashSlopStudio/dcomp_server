defmodule Dcomp.Repo.Migrations.CreateDecompTables do
  use Ecto.Migration

  def change do
    create table(:settings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :api_key_hash, :string
      add :poll_interval_s, :integer, null: false, default: 300
      add :layout_mode, :string, null: false, default: "size"

      timestamps(type: :utc_datetime)
    end

    create table(:games, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :slug, :string, null: false
      add :repo_url, :string, null: false
      add :branch, :string, null: false, default: "main"
      add :image_path, :string
      add :last_synced_sha, :string
      add :last_synced_at, :utc_datetime
      # Rules read from the repo's pool.toml on sync.
      add :claim_hours, :integer
      add :max_claims, :integer
      add :max_strikes, :integer

      timestamps(type: :utc_datetime)
    end

    create unique_index(:games, [:slug])

    create table(:contributors, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :login, :citext, null: false
      add :avatar_url, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:contributors, [:login])

    create table(:functions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :game_id, references(:games, type: :binary_id, on_delete: :delete_all), null: false
      add :addr, :string, null: false
      add :size, :integer, null: false
      add :sha1, :string, null: false
      add :status, :string, null: false, default: "unclaimed"
      add :claimed_by_id, references(:contributors, type: :binary_id, on_delete: :nilify_all)
      add :claimed_at, :utc_datetime
      add :solved_by_id, references(:contributors, type: :binary_id, on_delete: :nilify_all)
      add :solved_at, :utc_datetime
      add :solve_sha, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:functions, [:game_id, :addr])
    create index(:functions, [:game_id, :status])
    create index(:functions, [:solved_by_id])
    create index(:functions, [:claimed_by_id])

    create table(:events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :game_id, references(:games, type: :binary_id, on_delete: :delete_all), null: false
      add :type, :string, null: false
      add :contributor_id, references(:contributors, type: :binary_id, on_delete: :nilify_all)
      add :addr, :string, null: false
      add :sha, :string, null: false
      add :occurred_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    # Makes re-walking git history idempotent.
    create unique_index(:events, [:game_id, :sha, :type, :addr])
    create index(:events, [:game_id, :occurred_at])
    create index(:events, [:contributor_id])

    create table(:strikes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :game_id, references(:games, type: :binary_id, on_delete: :delete_all), null: false

      add :contributor_id, references(:contributors, type: :binary_id, on_delete: :delete_all),
        null: false

      add :count, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:strikes, [:game_id, :contributor_id])
  end
end
