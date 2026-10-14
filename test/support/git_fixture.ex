defmodule Dcomp.GitFixture do
  @moduledoc "Builds throwaway git repos shaped like a decomp pool repo, for sync tests."

  def init! do
    dir = Path.join(System.tmp_dir!(), "dcomp_fixture_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    git!(dir, ["init", "--quiet", "-b", "main"])
    dir
  end

  @doc "Writes `files` (`path => content`, or `path => :delete`) and commits them at `iso`."
  def commit!(dir, message, files, iso \\ "2026-01-01T00:00:00Z") do
    for {path, content} <- files do
      full = Path.join(dir, path)

      case content do
        :delete ->
          File.rm!(full)

        _ ->
          File.mkdir_p!(Path.dirname(full))
          File.write!(full, content)
      end
    end

    git!(dir, ["add", "-A"])

    git!(
      dir,
      [
        "-c",
        "user.name=t",
        "-c",
        "user.email=t@example.com",
        "-c",
        "commit.gpgsign=false",
        "commit",
        "--quiet",
        "--allow-empty",
        "-m",
        message
      ],
      [{"GIT_AUTHOR_DATE", iso}, {"GIT_COMMITTER_DATE", iso}]
    )

    git!(dir, ["rev-parse", "HEAD"]) |> String.trim()
  end

  @csv "addr,size,sha1\n08000100,100,aaa\n08000200,200,bbb\n08000300,300,ccc\n08000400,400,ddd\n"
  @toml "claim_hours = 48\nmax_claims = 5\nmax_strikes = 3\n"

  @doc "A repo with the pool layout and four functions (100, 200, 300, 400 bytes), nothing claimed."
  def pool_repo! do
    dir = init!()

    commit!(dir, "init", %{
      "functions.csv" => @csv,
      "pool.toml" => @toml,
      "pool/claims/.gitkeep" => "",
      "pool/strikes/.gitkeep" => "",
      "src/.gitkeep" => ""
    })

    dir
  end

  @doc """
  Plays every commit shape on a `pool_repo!/0`: claims, a solve, a release, an expiry (with its
  strike), a claim left open, and a solve with no claim.
  """
  def pool_history!(dir) do
    commit!(
      dir,
      "claim #1",
      %{"pool/claims/08000100" => "ana 2026-01-01T10:00:00Z\n"},
      "2026-01-01T10:00:05Z"
    )

    commit!(
      dir,
      "claim #2",
      %{"pool/claims/08000200" => "Bo 2026-01-01T11:00:00Z\n"},
      "2026-01-01T11:00:05Z"
    )

    commit!(
      dir,
      "solve #3",
      %{"src/func_08000100.c" => "int f(void){return 0;}\n", "pool/claims/08000100" => :delete},
      "2026-01-02T09:00:00Z"
    )

    commit!(dir, "release #4", %{"pool/claims/08000200" => :delete}, "2026-01-02T10:00:00Z")

    commit!(
      dir,
      "claim #5",
      %{"pool/claims/08000300" => "cy 2026-01-03T12:00:00Z\n"},
      "2026-01-03T12:00:05Z"
    )

    commit!(
      dir,
      "Expire claims",
      %{"pool/claims/08000300" => :delete, "pool/strikes/cy" => "1\n"},
      "2026-01-05T12:00:00Z"
    )

    commit!(
      dir,
      "claim #6",
      %{"pool/claims/08000400" => "ana 2026-01-06T08:00:00Z\n"},
      "2026-01-06T08:00:05Z"
    )

    commit!(
      dir,
      "solve #7",
      %{"src/func_08000200.c" => "int g(void){return 1;}\n"},
      "2026-01-07T09:00:00Z"
    )
  end

  defp git!(dir, args, env \\ []) do
    {out, 0} = System.cmd("git", ["-C", dir | args], env: env, stderr_to_stdout: true)
    out
  end
end
