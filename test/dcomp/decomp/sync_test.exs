defmodule Dcomp.Decomp.SyncTest do
  use Dcomp.DataCase, async: true

  import Ecto.Query

  alias Dcomp.Decomp.{Contributor, Event, Game, Strike, Sync}
  alias Dcomp.Decomp.Function, as: Func
  alias Dcomp.GitFixture

  setup do
    dir = GitFixture.pool_repo!()

    slug = "g#{System.unique_integer([:positive])}"
    game = Repo.insert!(%Game{name: "Fixture", slug: slug, repo_url: dir, branch: "main"})

    on_exit(fn ->
      File.rm_rf!(dir)
      File.rm_rf!(Dcomp.Decomp.Mirror.dir(game))
    end)

    %{dir: dir, game: game}
  end

  defp history(dir), do: GitFixture.pool_history!(dir)

  defp fns(game) do
    Repo.all(from f in Func, where: f.game_id == ^game.id, preload: [:claimed_by, :solved_by])
    |> Map.new(&{&1.addr, &1})
  end

  defp event_counts(game) do
    Repo.all(
      from e in Event,
        where: e.game_id == ^game.id,
        group_by: e.type,
        select: {e.type, count(e.id)}
    )
    |> Map.new()
  end

  test "syncs current state, attribution, events, strikes and rules", %{dir: dir, game: game} do
    history(dir)

    assert {:ok, game} = Sync.run(game)

    f = fns(game)
    assert f["08000100"].status == :solved
    assert f["08000100"].solved_by.login == "ana"
    assert f["08000100"].solved_at == ~U[2026-01-02 09:00:00Z]
    assert f["08000200"].status == :solved
    assert f["08000200"].solved_by == nil
    assert f["08000300"].status == :unclaimed
    assert f["08000400"].status == :claimed
    assert f["08000400"].claimed_by.login == "ana"
    assert f["08000400"].claimed_at == ~U[2026-01-06 08:00:00Z]
    assert f["08000100"].size == 100

    assert event_counts(game) == %{claim: 4, solve: 2, release: 1, expire: 1, strike: 1}

    claim =
      Repo.one!(
        from e in Event,
          where: e.game_id == ^game.id and e.type == :claim and e.addr == "08000200"
      )

    assert claim.occurred_at == ~U[2026-01-01 11:00:00Z]

    assert [%{count: 1}] = Repo.all(from s in Strike, where: s.game_id == ^game.id)
    assert Repo.get_by!(Contributor, login: "bo").avatar_url == "https://github.com/Bo.png"

    assert {game.claim_hours, game.max_claims, game.max_strikes} == {48, 5, 3}
    assert game.last_synced_sha
    assert game.last_sync_error == nil
  end

  test "is idempotent and picks up new commits incrementally", %{dir: dir, game: game} do
    history(dir)
    {:ok, game} = Sync.run(game)
    {:ok, game} = Sync.run(game)
    assert event_counts(game) == %{claim: 4, solve: 2, release: 1, expire: 1, strike: 1}
    assert Repo.aggregate(Func, :count) == 4

    GitFixture.commit!(
      dir,
      "solve #8",
      %{"src/func_08000400.c" => "int h(void){return 2;}\n", "pool/claims/08000400" => :delete},
      "2026-01-08T09:00:00Z"
    )

    {:ok, game} = Sync.run(game)
    f = fns(game)
    assert f["08000400"].status == :solved
    assert f["08000400"].solved_by.login == "ana"
    assert event_counts(game).solve == 3
    assert event_counts(game).claim == 4
  end

  test "functions removed from functions.csv are removed", %{dir: dir, game: game} do
    {:ok, game} = Sync.run(game)
    assert map_size(fns(game)) == 4

    GitFixture.commit!(dir, "fix boundaries", %{
      "functions.csv" => "addr,size,sha1\n08000100,100,aaa\n08000200,222,bbb\n"
    })

    {:ok, game} = Sync.run(game)
    f = fns(game)
    assert Map.keys(f) |> Enum.sort() == ["08000100", "08000200"]
    assert f["08000200"].size == 222
  end

  test "a malformed functions.csv fails the sync and keeps the last good data", %{
    dir: dir,
    game: game
  } do
    {:ok, game} = Sync.run(game)

    GitFixture.commit!(dir, "typo", %{"functions.csv" => "addr,size,sha1\n08000100,oops,aaa\n"})

    assert {:error, msg} = Sync.run(game)
    assert msg =~ "bad or duplicate row"
    assert map_size(fns(game)) == 4
  end

  test "a force-pushed branch drops the events of the abandoned commits", %{dir: dir, game: game} do
    history(dir)
    {:ok, game} = Sync.run(game)
    {old, 0} = System.cmd("git", ["-C", dir, "rev-parse", "HEAD"])
    old = String.trim(old)
    assert Repo.exists?(from e in Event, where: e.game_id == ^game.id and e.sha == ^old)

    {_, 0} = System.cmd("git", ["-C", dir, "reset", "--hard", "-q", "HEAD~1"])
    GitFixture.commit!(dir, "rewrite", %{"README" => "x"})

    {:ok, game} = Sync.run(game)
    refute Repo.exists?(from e in Event, where: e.game_id == ^game.id and e.sha == ^old)
  end

  test "recovers from a mirror directory left by an interrupted clone", %{game: game} do
    File.mkdir_p!(Dcomp.Decomp.Mirror.dir(game))
    assert {:ok, _} = Sync.run(game)
  end

  test "editing the repo URL points the mirror at the new one", %{game: game} do
    {:ok, game} = Sync.run(game)
    other = GitFixture.pool_repo!()
    on_exit(fn -> File.rm_rf!(other) end)

    GitFixture.commit!(other, "only here", %{
      "functions.csv" => "addr,size,sha1\n08000999,9,zzz\n"
    })

    {:ok, game} = Sync.run(%{game | repo_url: other})
    assert Map.keys(fns(game)) == ["08000999"]
  end

  test "ignores strike files that aren't GitHub logins", %{dir: dir, game: game} do
    GitFixture.commit!(dir, "strikes", %{
      "pool/strikes/not a login!" => "2\n",
      "pool/strikes/ok" => "-1\n"
    })

    {:ok, game} = Sync.run(game)
    assert Repo.aggregate(from(s in Strike, where: s.game_id == ^game.id), :count) == 0
  end

  test "records an error when the repo has no functions.csv", %{dir: dir, game: game} do
    GitFixture.commit!(dir, "break", %{"functions.csv" => :delete})
    assert {:error, msg} = Sync.run(game)
    assert msg =~ "functions.csv"
    assert Repo.reload!(game).last_sync_error =~ "functions.csv"
  end

  test "records an error when the branch doesn't exist", %{game: game} do
    game = %{game | branch: "nope"}
    assert {:error, msg} = Sync.run(game)
    assert msg =~ "nope"
  end

  test "broadcasts on the game topic", %{game: game} do
    Phoenix.PubSub.subscribe(Dcomp.PubSub, Sync.topic(game.slug))
    {:ok, _} = Sync.run(game)
    slug = game.slug
    assert_receive {:synced, ^slug}
  end
end
