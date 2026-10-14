defmodule Dcomp.Decomp.Metrics do
  @moduledoc """
  Everything the game page shows, derived from `functions` and `events`.

  `for_game/2` returns one map so a page costs a handful of queries per refresh.
  """

  import Ecto.Query

  alias Dcomp.Decomp.{Contributor, Event, Game, Strike}
  alias Dcomp.Decomp.Function, as: Func
  alias Dcomp.Repo

  @size_buckets [
    {"≤16 B", 16},
    {"17–64 B", 64},
    {"65–256 B", 256},
    {"257–1024 B", 1024},
    {"> 1 KiB", nil}
  ]
  @velocity_days 30
  @top_remaining 10
  @activity 10

  def for_game(%Game{} = game, now \\ DateTime.utc_now()) do
    totals = totals(game)
    solves = solve_history(game)
    pairs = claim_solve_durations(game)
    counts = event_counts(game)

    %{
      totals: totals,
      completion_pct: pct(totals.solved.bytes, totals.all.bytes),
      completion_pct_count: pct(totals.solved.count, totals.all.count),
      leaderboard: leaderboard(game),
      active_claims: active_claims(game, now),
      burn_up: burn_up(solves),
      velocity: velocity(solves, totals, now),
      top_remaining: top_remaining(game),
      size_distribution: size_distribution(game),
      median_claim_to_solve_s: median(pairs),
      conversion_rate: ratio(length(pairs), counts[:claim]),
      expired: counts[:expire],
      released: counts[:release],
      strikes: strikes(game),
      recent_activity: recent_activity(game)
    }
  end

  @doc "Share of the puzzle image that is revealed: by bytes in `:size` layout, by count in `:grid`."
  def revealed_pct(metrics, :size), do: metrics.completion_pct
  def revealed_pct(metrics, :grid), do: metrics.completion_pct_count

  @doc """
  Every function as `[addr, size, status, person, solve_sha]` (status 0 unclaimed, 1 claimed, 2 solved;
  person is an index into the returned people list, or `nil`) for drawing the puzzle.
  """
  def puzzle_pieces(%Game{} = game) do
    rows =
      from(f in Func,
        left_join: c in Contributor,
        on: c.id == coalesce(f.solved_by_id, f.claimed_by_id),
        where: f.game_id == ^game.id,
        order_by: f.addr,
        select: {f.addr, f.size, f.status, c.login, c.avatar_url, f.solve_sha}
      )
      |> Repo.all()

    people = rows |> Enum.map(&elem(&1, 3)) |> Enum.reject(&is_nil/1) |> Enum.uniq()
    index = people |> Enum.with_index() |> Map.new()
    avatars = for {_, _, _, l, a, _} <- rows, l, into: %{}, do: {l, a}

    pieces =
      for {addr, size, status, login, _, sha} <- rows do
        [addr, size, status_code(status), login && index[login], sha]
      end

    {pieces, Enum.map(people, &%{login: &1, avatar: avatars[&1]})}
  end

  defp status_code(:unclaimed), do: 0
  defp status_code(:claimed), do: 1
  defp status_code(:solved), do: 2

  ## Totals

  @doc "Solved/claimed/unclaimed/remaining/all, each as `%{count, bytes}`."
  def totals(game) do
    by_status =
      from(f in Func,
        where: f.game_id == ^game.id,
        group_by: f.status,
        select: {f.status, %{count: count(f.id), bytes: coalesce(sum(f.size), 0)}}
      )
      |> Repo.all()
      |> Map.new()

    empty = %{count: 0, bytes: 0}
    solved = Map.get(by_status, :solved, empty)
    claimed = Map.get(by_status, :claimed, empty)
    unclaimed = Map.get(by_status, :unclaimed, empty)

    %{
      solved: solved,
      claimed: claimed,
      unclaimed: unclaimed,
      remaining: %{count: claimed.count + unclaimed.count, bytes: claimed.bytes + unclaimed.bytes},
      all: %{
        count: solved.count + claimed.count + unclaimed.count,
        bytes: solved.bytes + claimed.bytes + unclaimed.bytes
      }
    }
  end

  ## People

  defp leaderboard(game) do
    from(f in Func,
      left_join: c in assoc(f, :solved_by),
      where: f.game_id == ^game.id and f.status == :solved,
      group_by: [c.id, c.login, c.avatar_url],
      order_by: [desc: count(f.id), desc: sum(f.size)],
      select: %{login: c.login, avatar_url: c.avatar_url, solves: count(f.id), bytes: sum(f.size)}
    )
    |> Repo.all()
    |> Enum.map(&Map.put(&1, :id, &1.login || "anonymous"))
  end

  defp active_claims(game, now) do
    hours = game.claim_hours

    from(f in Func,
      where: f.game_id == ^game.id and f.status == :claimed,
      order_by: f.claimed_at,
      preload: :claimed_by
    )
    |> Repo.all()
    |> Enum.map(fn f ->
      expires_at = f.claimed_at && hours && DateTime.add(f.claimed_at, hours * 3600)

      %{
        id: f.addr,
        addr: f.addr,
        size: f.size,
        login: f.claimed_by && f.claimed_by.login,
        avatar_url: f.claimed_by && f.claimed_by.avatar_url,
        claimed_at: f.claimed_at,
        expires_at: expires_at,
        stale?: expires_at != nil and DateTime.compare(expires_at, now) == :lt
      }
    end)
  end

  defp strikes(game) do
    from(s in Strike,
      join: c in Contributor,
      on: c.id == s.contributor_id,
      where: s.game_id == ^game.id,
      order_by: [desc: s.count, asc: c.login],
      select: %{id: c.login, login: c.login, avatar_url: c.avatar_url, count: s.count}
    )
    |> Repo.all()
    |> Enum.map(&Map.put(&1, :banned?, game.max_strikes != nil and &1.count >= game.max_strikes))
  end

  ## Time

  # [{addr, first_solved_at, size}]
  defp solve_history(game) do
    from(e in Event,
      join: f in Func,
      on: f.game_id == e.game_id and f.addr == e.addr,
      where: e.game_id == ^game.id and e.type == :solve,
      group_by: [e.addr, f.size],
      select: {e.addr, min(e.occurred_at), f.size}
    )
    |> Repo.all()
  end

  # Cumulative solved per day: [%{date, count, bytes}]
  defp burn_up(solves) do
    solves
    |> Enum.group_by(fn {_, at, _} -> DateTime.to_date(at) end)
    |> Enum.sort_by(fn {date, _} -> date end, Date)
    |> Enum.map_reduce({0, 0}, fn {date, rows}, {c, b} ->
      acc = {c + length(rows), b + (rows |> Enum.map(&elem(&1, 2)) |> Enum.sum())}
      {%{date: date, count: elem(acc, 0), bytes: elem(acc, 1)}, acc}
    end)
    |> elem(0)
  end

  # Solve rate over the last 30 days and the time that leaves, at that pace.
  defp velocity(solves, totals, now) do
    since = DateTime.add(now, -@velocity_days * 86_400)
    recent = Enum.filter(solves, fn {_, at, _} -> DateTime.compare(at, since) != :lt end)
    bytes = recent |> Enum.map(&elem(&1, 2)) |> Enum.sum()

    per_day_bytes = bytes / @velocity_days

    %{
      solves_per_day: length(recent) / @velocity_days,
      solves_24h: Enum.count(recent, fn {_, at, _} -> DateTime.diff(now, at) <= 86_400 end),
      solves_7d: Enum.count(recent, fn {_, at, _} -> DateTime.diff(now, at) <= 7 * 86_400 end),
      bytes_per_day: per_day_bytes,
      eta_days: if(per_day_bytes > 0, do: totals.remaining.bytes / per_day_bytes)
    }
  end

  # Seconds from a claim to the solve of that function by the same person. Solves without a
  # known solver, or without a prior claim by them, are left out.
  defp claim_solve_durations(game) do
    events =
      from(e in Event,
        where:
          e.game_id == ^game.id and e.type in [:claim, :solve] and not is_nil(e.contributor_id),
        order_by: e.occurred_at,
        select: {e.type, {e.addr, e.contributor_id}, e.occurred_at}
      )
      |> Repo.all()

    # claim times per {addr, person}, newest first
    claims =
      for {:claim, key, at} <- events, reduce: %{} do
        acc -> Map.update(acc, key, [at], &[at | &1])
      end

    for {:solve, key, solved_at} <- events,
        claimed_at =
          Enum.find(Map.get(claims, key, []), &(DateTime.compare(&1, solved_at) != :gt)),
        do: DateTime.diff(solved_at, claimed_at)
  end

  defp event_counts(game) do
    from(e in Event,
      where: e.game_id == ^game.id,
      group_by: e.type,
      select: {e.type, count(e.id)}
    )
    |> Repo.all()
    |> Map.new()
    |> then(&Map.merge(%{claim: 0, solve: 0, expire: 0, release: 0, strike: 0}, &1))
  end

  defp recent_activity(game) do
    from(e in Event,
      left_join: c in assoc(e, :contributor),
      left_join: f in Func,
      on: f.game_id == e.game_id and f.addr == e.addr,
      where: e.game_id == ^game.id and e.type in [:claim, :solve, :release, :expire],
      order_by: [desc: e.occurred_at, desc: e.inserted_at],
      limit: @activity,
      select: %{
        id: e.id,
        type: e.type,
        addr: e.addr,
        size: f.size,
        sha: e.sha,
        at: e.occurred_at,
        login: c.login,
        avatar_url: c.avatar_url
      }
    )
    |> Repo.all()
  end

  ## What's left

  defp top_remaining(game) do
    from(f in Func,
      where: f.game_id == ^game.id and f.status != :solved,
      order_by: [desc: f.size, asc: f.addr],
      limit: @top_remaining,
      select: %{id: f.addr, addr: f.addr, size: f.size, status: f.status}
    )
    |> Repo.all()
  end

  # Unsolved functions per size bucket: [%{label, count}]
  defp size_distribution(game) do
    sizes =
      Repo.all(
        from f in Func, where: f.game_id == ^game.id and f.status != :solved, select: f.size
      )

    {rows, _} =
      Enum.map_reduce(@size_buckets, 0, fn {label, max}, prev ->
        n = Enum.count(sizes, &(&1 > prev and (max == nil or &1 <= max)))
        {%{label: label, count: n}, max || prev}
      end)

    rows
  end

  ## Helpers

  defp pct(_part, 0), do: 0.0
  defp pct(part, whole), do: Float.round(part * 100 / whole, 1)

  defp ratio(_n, 0), do: nil
  defp ratio(n, d), do: Float.round(n / d, 3)

  defp median([]), do: nil

  defp median(list) do
    sorted = Enum.sort(list)
    mid = div(length(sorted), 2)

    if rem(length(sorted), 2) == 1,
      do: Enum.at(sorted, mid),
      else: (Enum.at(sorted, mid - 1) + Enum.at(sorted, mid)) / 2
  end
end
