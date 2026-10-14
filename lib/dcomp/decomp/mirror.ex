defmodule Dcomp.Decomp.Mirror do
  @moduledoc """
  Local bare mirror of a game's git repo, read with plain `git` (no GitHub API, so no rate limits).

  All commands run without a shell and with only the transports in `:git_protocols` allowed.
  """

  alias Dcomp.Decomp.Game

  @type commit :: %{sha: String.t(), at: DateTime.t(), changes: [{String.t(), String.t()}]}

  def dir(%Game{slug: slug}), do: Path.join(Application.fetch_env!(:dcomp, :mirror_dir), slug)

  @doc "Clones the mirror on first use, otherwise fetches. Returns `:ok` or `{:error, output}`."
  def fetch(%Game{repo_url: url} = game) do
    dir = dir(game)

    if File.dir?(dir) do
      # The URL can be edited after the first clone, so point origin at the current one.
      with {_, 0} <- git(["-C", dir, "remote", "set-url", "origin", "--", url]) do
        ok(git(["-C", dir, "fetch", "--prune", "--quiet", "origin"], safe: true))
      else
        failed -> ok(failed)
      end
    else
      File.mkdir_p!(Path.dirname(dir))
      ok(git(["clone", "--mirror", "--quiet", "--", url, dir], safe: true))
    end
  end

  @doc "Deletes the local mirror (the slug is validated to lowercase letters, digits and dashes)."
  def remove(%Game{} = game), do: File.rm_rf(dir(game))

  @doc "Commit sha of the game's branch."
  def head(%Game{branch: branch} = game) do
    case git([
           "-C",
           dir(game),
           "rev-parse",
           "--verify",
           "--quiet",
           "refs/heads/#{branch}^{commit}"
         ]) do
      {out, 0} -> {:ok, String.trim(out)}
      {out, _} -> {:error, "branch #{branch} not found: #{out}"}
    end
  end

  @doc "File contents at `rev`, or `nil` if the path doesn't exist there."
  def read(game, rev, path) do
    case git(["-C", dir(game), "show", "#{rev}:#{path}"]) do
      {out, 0} -> out
      _ -> nil
    end
  end

  @doc "File names (not paths) directly under `path` at `rev`."
  def ls(game, rev, path) do
    case git(["-C", dir(game), "ls-tree", "--name-only", rev, "#{path}/"]) do
      {out, 0} -> out |> String.split("\n", trim: true) |> Enum.map(&Path.basename/1)
      _ -> []
    end
  end

  @doc "Whether `ancestor` is reachable from `rev`."
  def ancestor?(game, ancestor, rev) do
    match?({_, 0}, git(["-C", dir(game), "merge-base", "--is-ancestor", ancestor, rev]))
  end

  @doc """
  Commits in `from..to` (all history up to `to` when `from` is `nil`), oldest first.

  Follows the first parent, so a merge commit reports the whole change a PR brought in.
  Each change is `{status, path}` with status `"A"`, `"M"` or `"D"`.
  """
  @spec log(Game.t(), String.t() | nil, String.t()) :: [commit]
  def log(game, from, to) do
    range = if from, do: "#{from}..#{to}", else: to

    {out, 0} =
      git([
        "-C",
        dir(game),
        "log",
        "--reverse",
        "--first-parent",
        "-m",
        "--no-renames",
        "--name-status",
        "--format=%x01%H%x02%cI",
        range
      ])

    out |> String.split("\x01", trim: true) |> Enum.map(&parse_commit/1)
  end

  defp parse_commit(block) do
    [header | lines] = String.split(block, "\n", trim: true)
    [sha, iso] = String.split(header, "\x02")
    {:ok, at, _} = DateTime.from_iso8601(iso)

    changes =
      for line <- lines,
          [status, path] <- [String.split(line, "\t", parts: 2)],
          do: {status, path}

    %{sha: sha, at: at, changes: changes}
  end

  defp git(args, opts \\ []) do
    protocols =
      if opts[:safe] do
        # ponytail: aborts transfers slower than 1 kB/s for 60 s, which bounds a stalled remote
        # but not a connect that hangs; wrap git in a killable Port if that ever bites.
        ["-c", "http.lowSpeedLimit=1000", "-c", "http.lowSpeedTime=60"] ++
          ["-c", "protocol.allow=never"] ++
          Enum.flat_map(
            Application.fetch_env!(:dcomp, :git_protocols),
            &["-c", "protocol.#{&1}.allow=always"]
          )
      else
        []
      end

    System.cmd("git", protocols ++ args,
      env: [{"GIT_TERMINAL_PROMPT", "0"}],
      stderr_to_stdout: true
    )
  end

  defp ok({_, 0}), do: :ok
  defp ok({out, _}), do: {:error, String.trim(out)}
end
