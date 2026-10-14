defmodule Dcomp.Decomp.Syncer do
  @moduledoc """
  Keeps every game in sync with its repo.

  Polls all games on the interval stored in `Dcomp.Decomp.Setting` (re-read after every run, so
  admin changes apply without a restart) and syncs one game early when `nudge/1` is called
  (the webhook). One process runs all syncs, so a game is never synced twice at once.
  """
  use GenServer

  require Logger

  alias Dcomp.Decomp
  alias Dcomp.Decomp.Sync

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc "Asks for a sync of one game soon. Returns immediately."
  def nudge(slug, server \\ __MODULE__), do: GenServer.cast(server, {:sync, slug})

  @impl true
  def init(opts) do
    schedule(Keyword.get(opts, :initial_delay_ms, 5_000))
    {:ok, %{}}
  end

  @impl true
  def handle_info(:tick, state) do
    Enum.each(Decomp.list_games(), &sync/1)
    schedule(Decomp.get_settings().poll_interval_s * 1000)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:sync, slug}, state) do
    if game = Decomp.get_game_by_slug(slug), do: sync(game)
    {:noreply, state}
  end

  # ponytail: syncs run inline, so a first clone of a huge repo delays other games and nudges;
  # move to Task.Supervisor with a per-game lock if that starts to hurt.
  defp sync(game) do
    case Sync.run(game) do
      {:ok, _} -> :ok
      {:error, reason} -> Logger.warning("sync #{game.slug} failed: #{reason}")
    end
  rescue
    e ->
      Logger.error("sync #{game.slug} crashed: #{Exception.message(e)}")

      game
      |> Decomp.Game.sync_changeset(%{last_sync_error: Exception.message(e)})
      |> Dcomp.Repo.update()
  end

  defp schedule(:infinity), do: :ok
  defp schedule(ms), do: Process.send_after(self(), :tick, ms)
end
