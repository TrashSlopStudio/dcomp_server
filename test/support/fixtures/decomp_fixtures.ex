defmodule Dcomp.DecompFixtures do
  @moduledoc "Test helpers for decomp games."

  alias Dcomp.Decomp.{Game, Mirror, Sync}
  alias Dcomp.{GitFixture, Repo}

  @doc """
  A game synced from a fixture repo with the full pool history: ana solved 08000100 and claims
  08000400, an unknown solver solved 08000200, cy has a strike. Cleans up after the test.
  """
  def synced_game_fixture(attrs \\ %{}) do
    dir = GitFixture.pool_repo!()
    GitFixture.pool_history!(dir)
    slug = Map.get(attrs, :slug, "g#{System.unique_integer([:positive])}")
    name = Map.get(attrs, :name, "Fixture #{slug}")
    game = Repo.insert!(%Game{name: name, slug: slug, repo_url: dir, branch: "main"})
    {:ok, game} = Sync.run(game)

    ExUnit.Callbacks.on_exit(fn ->
      File.rm_rf!(dir)
      File.rm_rf!(Mirror.dir(game))
    end)

    game
  end

  def game_fixture(attrs \\ %{}) do
    n = System.unique_integer([:positive])

    attrs =
      Enum.into(attrs, %{name: "Game #{n}", repo_url: "https://example.com/o/r#{n}"})

    {:ok, game} = Dcomp.Decomp.create_game(attrs)
    game
  end

  def png_bytes, do: <<0x89, "PNG\r\n", 0x1A, 0x0A>> <> :crypto.strong_rand_bytes(64)
end
