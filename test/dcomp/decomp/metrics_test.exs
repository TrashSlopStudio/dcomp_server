defmodule Dcomp.Decomp.MetricsTest do
  use Dcomp.DataCase, async: true

  alias Dcomp.Decomp.{Game, Metrics, Mirror, Sync}
  alias Dcomp.GitFixture

  @now ~U[2026-01-10 00:00:00Z]

  setup do
    dir = GitFixture.pool_repo!()
    GitFixture.pool_history!(dir)
    slug = "m#{System.unique_integer([:positive])}"
    game = Repo.insert!(%Game{name: "M", slug: slug, repo_url: dir, branch: "main"})
    {:ok, game} = Sync.run(game)

    on_exit(fn ->
      File.rm_rf!(dir)
      File.rm_rf!(Mirror.dir(game))
    end)

    %{game: game, m: Metrics.for_game(game, @now)}
  end

  test "totals and completion", %{m: m} do
    assert m.totals.solved == %{count: 2, bytes: 300}
    assert m.totals.claimed == %{count: 1, bytes: 400}
    assert m.totals.unclaimed == %{count: 1, bytes: 300}
    assert m.totals.remaining == %{count: 2, bytes: 700}
    assert m.totals.all == %{count: 4, bytes: 1000}
    assert m.completion_pct == 30.0
    assert m.completion_pct_count == 50.0
    assert Metrics.revealed_pct(m, :size) == 30.0
    assert Metrics.revealed_pct(m, :grid) == 50.0
  end

  test "leaderboard includes the anonymous solver", %{m: m} do
    assert [%{login: nil, solves: 1, bytes: 200}, %{login: "ana", solves: 1, bytes: 100}] =
             m.leaderboard
  end

  test "active claims carry an expiry and a stale flag", %{m: m} do
    assert [c] = m.active_claims
    assert c.login == "ana" and c.addr == "08000400"
    assert c.expires_at == ~U[2026-01-08 08:00:00Z]
    assert c.stale?
  end

  test "burn-up, velocity and ETA", %{m: m} do
    assert [%{count: 1, bytes: 100}, %{count: 2, bytes: 300}] = m.burn_up
    assert m.velocity.solves_7d == 1
    assert_in_delta m.velocity.solves_per_day, 2 / 30, 1.0e-9
    assert_in_delta m.velocity.bytes_per_day, 10.0, 1.0e-9
    assert_in_delta m.velocity.eta_days, 70.0, 1.0e-9
  end

  test "what is left", %{m: m} do
    assert [%{addr: "08000400", size: 400}, %{addr: "08000300", size: 300}] = m.top_remaining
    assert Enum.find(m.size_distribution, &(&1.label == "257–1024 B")).count == 2
    assert Enum.sum(Enum.map(m.size_distribution, & &1.count)) == 2
  end

  test "claim to solve only pairs a person with their own claim", %{m: m} do
    # ana: 10:00 claim -> next day 09:00 solve. Bo's released claim must not pair with the later anonymous solve.
    assert m.median_claim_to_solve_s == 23 * 3600
    assert m.conversion_rate == 0.25
  end

  test "expiries, releases, strikes", %{m: m} do
    assert m.expired == 1
    assert m.released == 1
    assert [%{login: "cy", count: 1, banned?: false}] = m.strikes
  end

  test "recent activity is newest first", %{m: m} do
    assert [%{type: :solve, addr: "08000200", login: nil} | _] = m.recent_activity
    # 4 claims + 2 solves + release + expiry; the strike duplicates the expiry so it is not listed
    assert length(m.recent_activity) == 8
  end

  test "an empty game has zeroes, not crashes" do
    game = Repo.insert!(%Game{name: "E", slug: "empty", repo_url: "x", branch: "main"})
    m = Metrics.for_game(game, @now)
    assert m.completion_pct == 0.0
    assert m.leaderboard == []
    assert m.velocity.eta_days == nil
    assert m.median_claim_to_solve_s == nil
    assert m.conversion_rate == nil
  end
end
