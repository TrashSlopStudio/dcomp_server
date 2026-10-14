defmodule Dcomp.Decomp.Sync do
  @moduledoc """
  Brings the database in line with a game's git repo.

  The repo at the branch head is the source of truth for the *current* state
  (`functions.csv`, `pool/claims`, `pool/strikes`, `src/`, `pool.toml`). The commits since
  the last sync only add history (`events`), and re-reading a commit is harmless because
  events are unique per `(game, sha, type, addr)`.

  Commit shapes this understands (see the decomp pool tooling):

    * claim   - adds `pool/claims/ADDR` (`<login> <iso8601>`)
    * solve   - adds `src/func_ADDR.c` and deletes the claim; the solver is the login in the
      claim file at the parent commit
    * expire  - deletes a claim and writes `pool/strikes/<login>` in the same commit
    * release - deletes a claim and nothing else
  """

  import Ecto.Query

  alias Dcomp.Decomp.{Contributor, Event, Game, Mirror, Strike}
  alias Dcomp.Decomp.Function, as: Func
  alias Dcomp.Repo

  # Postgres allows 65_535 bind params per statement.
  @chunk 1000

  def topic(slug), do: "game:" <> slug

  @doc "Fetches the repo and syncs. Records any failure on the game as `last_sync_error`."
  def run(%Game{} = game) do
    case do_run(game) do
      {:ok, game} ->
        broadcast(game)
        {:ok, game}

      {:error, reason} ->
        reason = to_string(reason)
        game |> Game.sync_changeset(%{last_sync_error: reason}) |> Repo.update()
        broadcast(game)
        {:error, reason}
    end
  end

  # Also sent after a failure, so open pages reload and show the sync error.
  defp broadcast(game),
    do: Phoenix.PubSub.broadcast(Dcomp.PubSub, topic(game.slug), {:synced, game.slug})

  defp do_run(game) do
    with :ok <- Mirror.fetch(game),
         {:ok, head} <- Mirror.head(game),
         {:ok, state} <- read_state(game, head) do
      {commits, rebuild?} = commits_since(game, head)
      events = Enum.flat_map(commits, &events_for(game, &1))
      persist(game, head, state, events, rebuild?)
    end
  end

  ## Reading the repo at head

  defp read_state(game, head) do
    case Mirror.read(game, head, "functions.csv") do
      nil ->
        {:error, "functions.csv not found at #{String.slice(head, 0, 8)}"}

      csv ->
        with {:ok, functions} <- parse_csv(csv) do
          {:ok,
           %{
             functions: functions,
             rules: parse_rules(Mirror.read(game, head, "pool.toml") || ""),
             solved: solved_addrs(Mirror.ls(game, head, "src")),
             claims: read_claims(game, head),
             strikes: read_strikes(game, head)
           }}
        end
    end
  end

  # Strict on purpose: the sync deletes every function missing from the result, so a typo must
  # fail the sync (keeping the last good data) instead of silently dropping a row.
  defp parse_csv(csv) do
    rows =
      csv
      |> String.split("\n", trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == "" or &1 == "addr,size,sha1"))

    rows
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, [], MapSet.new()}, fn {line, n}, {:ok, acc, seen} ->
      with [addr, size, sha1] <- String.split(line, ","),
           true <- hex?(addr),
           {size, ""} when size >= 0 <- Integer.parse(size),
           addr = String.upcase(addr),
           false <- MapSet.member?(seen, addr) do
        {:cont, {:ok, [%{addr: addr, size: size, sha1: sha1} | acc], MapSet.put(seen, addr)}}
      else
        _ ->
          {:halt,
           {:error, "functions.csv: bad or duplicate row #{n}: #{String.slice(line, 0, 60)}"}}
      end
    end)
    |> case do
      {:ok, list, _seen} -> {:ok, Enum.reverse(list)}
      error -> error
    end
  end

  # ponytail: regex over the three top-level integer keys; use a TOML parser if pool.toml grows.
  defp parse_rules(toml) do
    for key <- ~w(claim_hours max_claims max_strikes), into: %{} do
      case Regex.run(~r/^\s*#{key}\s*=\s*(\d+)/m, toml) do
        [_, n] -> {String.to_existing_atom(key), String.to_integer(n)}
        nil -> {String.to_existing_atom(key), nil}
      end
    end
  end

  defp solved_addrs(names) do
    for name <- names,
        [_, addr] <- [Regex.run(~r/^func_([0-9A-Fa-f]+)\.c$/, name)],
        into: MapSet.new() do
      String.upcase(addr)
    end
  end

  defp read_claims(game, rev) do
    for name <-
          game |> Mirror.ls(rev, "pool/claims") |> Enum.reject(&String.starts_with?(&1, ".")),
        claim = parse_claim(Mirror.read(game, rev, "pool/claims/#{name}")),
        into: %{} do
      {String.upcase(name), claim}
    end
  end

  # "<login> <iso8601>\n" -> {login, datetime | nil}
  defp parse_claim(nil), do: nil

  defp parse_claim(content) do
    case String.split(content) do
      [login, ts | _] -> valid_login(login, parse_time(ts))
      [login] -> valid_login(login, nil)
      [] -> nil
    end
  end

  # Logins come from repo files, so anything that isn't a GitHub login is dropped before it can
  # reach a URL or a page.
  defp valid_login(login, ts), do: if(login?(login), do: {login, ts})

  defp login?(name), do: name =~ ~r/^[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})$/

  defp parse_time(ts) do
    case DateTime.from_iso8601(ts) do
      {:ok, dt, _} -> DateTime.truncate(dt, :second)
      _ -> nil
    end
  end

  defp read_strikes(game, rev) do
    for name <-
          game |> Mirror.ls(rev, "pool/strikes") |> Enum.reject(&String.starts_with?(&1, ".")),
        login?(name),
        {n, _} <- [
          Integer.parse(String.trim(Mirror.read(game, rev, "pool/strikes/#{name}") || ""))
        ],
        n >= 0,
        into: %{} do
      {name, n}
    end
  end

  ## History

  # `rebuild?` is true when the branch no longer contains the last synced commit (force-push or
  # branch change): the whole history is replayed and the old events are dropped.
  defp commits_since(%Game{last_synced_sha: nil} = game, head),
    do: {Mirror.log(game, nil, head), false}

  defp commits_since(%Game{last_synced_sha: from} = game, head) do
    if Mirror.ancestor?(game, from, head),
      do: {Mirror.log(game, from, head), false},
      else: {Mirror.log(game, nil, head), true}
  end

  # Returns [%{type, addr, sha, at, login}] for one commit.
  defp events_for(game, %{sha: sha, at: at, changes: changes}) do
    ctx = %{game: game, sha: sha, at: at}

    solved =
      for {"A", "src/func_" <> f} <- changes, addr = src_addr(f), into: MapSet.new(), do: addr

    struck =
      for {s, "pool/strikes/" <> l} <- changes,
          s in ["A", "M"],
          into: MapSet.new(),
          do: String.downcase(l)

    deleted = for {"D", "pool/claims/" <> a} <- changes, hex?(a), do: a
    added = for {"A", "pool/claims/" <> a} <- changes, hex?(a), do: a

    Enum.map(added, &claim_event(ctx, &1)) ++
      Enum.flat_map(deleted, &ended_events(ctx, &1, solved, struck)) ++
      unclaimed_solves(ctx, solved, deleted)
  end

  defp claim_event(%{game: game, sha: sha, at: at}, name) do
    {login, ts} = parse_claim(Mirror.read(game, sha, "pool/claims/#{name}")) || {nil, nil}
    %{type: :claim, addr: String.upcase(name), sha: sha, at: ts || at, login: login}
  end

  # A claim file was deleted: it was solved, it expired (the bot also wrote the strike), or the
  # claimer released it.
  defp ended_events(%{game: game, sha: sha, at: at}, name, solved, struck) do
    addr = String.upcase(name)
    {login, _} = parse_claim(Mirror.read(game, sha <> "^1", "pool/claims/#{name}")) || {nil, nil}
    ev = fn type -> %{type: type, addr: addr, sha: sha, at: at, login: login} end

    cond do
      MapSet.member?(solved, addr) -> [ev.(:solve)]
      login && String.downcase(login) in struck -> [ev.(:expire), ev.(:strike)]
      true -> [ev.(:release)]
    end
  end

  # Solved without a claim in the same commit: solver unknown (shown as anonymous).
  defp unclaimed_solves(%{sha: sha, at: at}, solved, deleted) do
    claimed = MapSet.new(deleted, &String.upcase/1)

    for addr <- solved, not MapSet.member?(claimed, addr) do
      %{type: :solve, addr: addr, sha: sha, at: at, login: nil}
    end
  end

  # Claim files are named after the function address; this skips .gitkeep and friends.
  defp hex?(name), do: name =~ ~r/^[0-9A-Fa-f]+$/

  defp src_addr(file) do
    case Regex.run(~r/^([0-9A-Fa-f]+)\.c$/, file) do
      [_, addr] -> String.upcase(addr)
      nil -> nil
    end
  end

  ## Persisting

  defp persist(game, head, state, events, rebuild?) do
    now = DateTime.utc_now(:second)

    result =
      Repo.transaction(fn ->
        if rebuild?, do: Repo.delete_all(from e in Event, where: e.game_id == ^game.id)
        ids = upsert_contributors(state, events, now)
        insert_events(game, events, ids, now)
        sync_functions(game, state, ids, now)
        sync_strikes(game, state.strikes, ids, now)

        game
        |> Game.sync_changeset(
          Map.merge(state.rules, %{
            last_synced_sha: head,
            last_synced_at: now,
            last_sync_error: nil
          })
        )
        |> Repo.update!()
      end)

    result
  end

  # Returns %{downcased_login => id}.
  defp upsert_contributors(state, events, now) do
    logins =
      [
        Enum.map(events, & &1.login),
        Enum.map(Map.values(state.claims), &elem(&1, 0)),
        Map.keys(state.strikes)
      ]
      |> List.flatten()
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq_by(&String.downcase/1)

    rows =
      for login <- logins do
        %{
          id: Ecto.UUID.generate(),
          login: login,
          avatar_url: Contributor.avatar_url_for(login),
          inserted_at: now,
          updated_at: now
        }
      end

    insert_chunks(Contributor, rows, on_conflict: :nothing, conflict_target: :login)

    Repo.all(from c in Contributor, where: c.login in ^logins, select: {c.login, c.id})
    |> Map.new(fn {login, id} -> {String.downcase(login), id} end)
  end

  defp insert_events(game, events, ids, now) do
    rows =
      for e <- events do
        %{
          id: Ecto.UUID.generate(),
          game_id: game.id,
          type: e.type,
          addr: e.addr,
          sha: e.sha,
          occurred_at: e.at,
          contributor_id: e.login && ids[String.downcase(e.login)],
          inserted_at: now
        }
      end

    insert_chunks(Event, rows,
      on_conflict: :nothing,
      conflict_target: [:game_id, :sha, :type, :addr]
    )
  end

  defp sync_functions(game, state, ids, now) do
    solves =
      from(e in Event,
        where: e.game_id == ^game.id and e.type == :solve,
        order_by: e.occurred_at,
        select: {e.addr, {e.contributor_id, e.occurred_at, e.sha}}
      )
      |> Repo.all()
      |> Map.new()

    rows = Enum.map(state.functions, &function_row(&1, game, state, solves, ids, now))

    insert_chunks(Func, rows,
      on_conflict:
        {:replace,
         [
           :size,
           :sha1,
           :status,
           :claimed_by_id,
           :claimed_at,
           :solved_by_id,
           :solved_at,
           :solve_sha,
           :updated_at
         ]},
      conflict_target: [:game_id, :addr]
    )

    addrs = Enum.map(state.functions, & &1.addr)
    Repo.delete_all(from f in Func, where: f.game_id == ^game.id and f.addr not in ^addrs)
  end

  defp function_row(%{addr: addr} = fun, game, state, solves, ids, now) do
    base = %{
      id: Ecto.UUID.generate(),
      game_id: game.id,
      addr: addr,
      size: fun.size,
      sha1: fun.sha1,
      status: :unclaimed,
      claimed_by_id: nil,
      claimed_at: nil,
      solved_by_id: nil,
      solved_at: nil,
      solve_sha: nil,
      inserted_at: now,
      updated_at: now
    }

    cond do
      addr in state.solved ->
        {by, at, sha} = Map.get(solves, addr, {nil, nil, nil})
        %{base | status: :solved, solved_by_id: by, solved_at: at, solve_sha: sha}

      claim = state.claims[addr] ->
        {login, ts} = claim
        %{base | status: :claimed, claimed_by_id: ids[String.downcase(login)], claimed_at: ts}

      true ->
        base
    end
  end

  defp sync_strikes(game, strikes, ids, now) do
    Repo.delete_all(from s in Strike, where: s.game_id == ^game.id)

    rows =
      for {login, count} <- strikes, id = ids[String.downcase(login)] do
        %{
          id: Ecto.UUID.generate(),
          game_id: game.id,
          contributor_id: id,
          count: count,
          inserted_at: now,
          updated_at: now
        }
      end

    insert_chunks(Strike, rows, [])
  end

  defp insert_chunks(schema, rows, opts) do
    rows |> Enum.chunk_every(@chunk) |> Enum.each(&Repo.insert_all(schema, &1, opts))
  end
end
