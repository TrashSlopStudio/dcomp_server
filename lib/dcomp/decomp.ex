defmodule Dcomp.Decomp do
  @moduledoc """
  Games, site settings and the global API key.

  Sync (`Dcomp.Decomp.Sync`) and reporting (`Dcomp.Decomp.Metrics`) build on these.
  """

  import Ecto.Query

  alias Dcomp.Decomp.{Game, Mirror, Setting}
  alias Dcomp.Repo

  ## Settings

  @doc "Returns the single settings row, creating it with defaults on first use."
  def get_settings do
    Repo.one(from s in Setting, limit: 1) || insert_settings()
  end

  # Two first requests can race; the singleton index makes the loser a no-op, so both read one row.
  defp insert_settings do
    Repo.insert!(%Setting{}, on_conflict: :nothing)
    Repo.one!(from s in Setting, limit: 1)
  end

  def change_settings(%Setting{} = setting, attrs \\ %{}), do: Setting.changeset(setting, attrs)

  def update_settings(%Setting{} = setting, attrs) do
    setting |> Setting.changeset(attrs) |> Repo.update()
  end

  ## API key

  @doc """
  Generates a new API key, stores only its hash and returns `{:ok, plain_key}`.

  The plain key is not recoverable afterwards, so show it once.
  """
  def rotate_api_key do
    key = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)

    with {:ok, _} <- get_settings() |> Setting.api_key_changeset(hash_key(key)) |> Repo.update() do
      {:ok, key}
    end
  end

  @doc "Constant-time check of a presented API key against the stored hash."
  def valid_api_key?(key) when is_binary(key) do
    case get_settings().api_key_hash do
      nil -> false
      hash -> Plug.Crypto.secure_compare(hash_key(key), hash)
    end
  end

  def valid_api_key?(_), do: false

  defp hash_key(key), do: :crypto.hash(:sha256, key) |> Base.encode16(case: :lower)

  ## Games

  def list_games, do: Repo.all(from g in Game, order_by: g.name)

  def get_game!(id), do: Repo.get!(Game, id)

  def get_game(id), do: Repo.get(Game, id)

  def get_game_by_slug(slug), do: Repo.get_by(Game, slug: slug)

  def get_game_by_slug!(slug), do: Repo.get_by!(Game, slug: slug)

  def change_game(%Game{} = game, attrs \\ %{}), do: Game.changeset(game, attrs)

  def create_game(attrs), do: %Game{} |> Game.changeset(attrs) |> Repo.insert()

  def update_game(%Game{} = game, attrs), do: game |> Game.changeset(attrs) |> Repo.update()

  def set_game_image(%Game{} = game, image_path) do
    game |> Game.image_changeset(image_path) |> Repo.update()
  end

  def delete_game(%Game{} = game) do
    with {:ok, game} <- Repo.delete(game) do
      Mirror.remove(game)
      {:ok, game}
    end
  end
end
