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

  @doc "Restarts the poll timer with the current interval setting (call after changing it)."
  def reschedule(server \\ __MODULE__), do: GenServer.cast(server, :reschedule)

  @impl true
  def init(opts) do
    {:ok, schedule(%{timer: nil, tick: nil}, Keyword.get(opts, :initial_delay_ms, 5_000))}
  end

  # Each timer carries a ref and only the latest one counts: a tick that was already in the
  # mailbox when `reschedule/0` ran can't start a second chain.
  @impl true
  def handle_info({:tick, ref}, %{tick: ref} = state) do
    Enum.each(Decomp.list_games(), &sync/1)
    {:noreply, schedule(state, interval_ms())}
  end

  def handle_info({:tick, _stale}, state), do: {:noreply, state}

  @impl true
  def handle_cast(:reschedule, %{timer: timer} = state) do
    if timer, do: Process.cancel_timer(timer)
    {:noreply, schedule(state, interval_ms())}
  end

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
      record_crash(game, Exception.message(e))
  end

  # Best effort: the game may be gone (deleted mid-sync) or the database down, and a failure here
  # must not take the syncer down with it.
  defp record_crash(game, message) do
    game |> Decomp.Game.sync_changeset(%{last_sync_error: message}) |> Dcomp.Repo.update()
  rescue
    e -> Logger.error("could not record the failure of #{game.slug}: #{Exception.message(e)}")
  end

  defp interval_ms, do: Decomp.get_settings().poll_interval_s * 1000

  defp schedule(state, :infinity), do: %{state | timer: nil, tick: nil}

  defp schedule(state, ms) do
    ref = make_ref()
    %{state | timer: Process.send_after(self(), {:tick, ref}, ms), tick: ref}
  end
end
