defmodule Dcomp.Decomp.SyncerTest do
  # async: false - the Syncer process needs the shared sandbox connection
  use Dcomp.DataCase, async: false

  alias Dcomp.Decomp.{Game, Mirror, Sync, Syncer}
  alias Dcomp.GitFixture

  setup do
    dir = GitFixture.init!()
    GitFixture.commit!(dir, "init", %{"functions.csv" => "addr,size,sha1\n08000100,10,aaa\n"})
    slug = "s#{System.unique_integer([:positive])}"
    game = Repo.insert!(%Game{name: "S", slug: slug, repo_url: dir, branch: "main"})

    on_exit(fn ->
      File.rm_rf!(dir)
      File.rm_rf!(Mirror.dir(game))
    end)

    %{game: game}
  end

  test "nudge/1 syncs the game", %{game: game} do
    Phoenix.PubSub.subscribe(Dcomp.PubSub, Sync.topic(game.slug))
    pid = start_supervised!({Syncer, name: :nudge_syncer, initial_delay_ms: :infinity})
    Syncer.nudge(game.slug, pid)
    slug = game.slug
    assert_receive {:synced, ^slug}, 5_000
    assert Repo.reload!(game).last_synced_sha
  end

  test "polls on its own and survives a broken game", %{game: game} do
    Repo.insert!(%Game{name: "Bad", slug: "bad", repo_url: "/nonexistent/repo", branch: "main"})
    Phoenix.PubSub.subscribe(Dcomp.PubSub, Sync.topic(game.slug))
    start_supervised!({Syncer, name: :poll_syncer, initial_delay_ms: 10})
    slug = game.slug
    assert_receive {:synced, ^slug}, 5_000
    assert Repo.get_by!(Game, slug: "bad").last_sync_error
  end
end
