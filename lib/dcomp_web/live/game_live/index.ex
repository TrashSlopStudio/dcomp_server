defmodule DcompWeb.GameLive.Index do
  @moduledoc "Public showcase of every decompilation project."
  use DcompWeb, :live_view

  import DcompWeb.GameComponents

  alias Dcomp.Decomp
  alias Dcomp.Decomp.{Metrics, Sync}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} wide>
      <section
        id="hero"
        class="relative overflow-hidden rounded-3xl border border-base-300 bg-base-200/50 px-6 py-14 text-center sm:px-12"
      >
        <div class="pointer-events-none absolute inset-0 bg-gradient-to-br from-primary/15 via-transparent to-accent/15" />
        <div class="relative">
          <p class="text-xs font-semibold uppercase tracking-[0.2em] text-primary">
            Community decompilation
          </p>
          <h1 class="mt-3 text-4xl font-bold tracking-tight sm:text-5xl">
            Piece by piece, byte for byte
          </h1>
          <p class="mx-auto mt-4 max-w-xl text-base-content/70">
            Pick a project, claim a function and solve it. Every solved function brings the game closer to being fully decompiled.
          </p>
        </div>
      </section>

      <details
        id="get-started"
        class="group mb-8 rounded-2xl border border-base-300 bg-base-200/50 px-6 py-4"
      >
        <summary class="flex cursor-pointer list-none items-center justify-between gap-3 font-semibold">
          <span class="flex items-center gap-2">
            <.icon name="hero-information-circle" class="size-5 text-primary" />
            How contributing works
          </span>
          <.icon
            name="hero-chevron-down"
            class="size-5 text-base-content/60 transition group-open:rotate-180"
          />
        </summary>
        <div class="mt-4 space-y-3 text-sm text-base-content/80">
          <p>
            Each project is a git repository. You claim a function with a pull request, write C that compiles to exactly the original bytes, then open another pull request with the solution. CI checks and merges both, and this site picks them up on the next sync.
          </p>
          <p>
            You can do it by hand or let your own
            <a
              href="https://claude.com/claude-code"
              target="_blank"
              rel="noopener"
              class="text-primary underline"
            >Claude Code</a>
            session do the matching. You bring your own legally obtained copy of the game, which is never uploaded or shared here.
          </p>
          <p>
            Open a project below for its repository, setup and rules.
          </p>
        </div>
      </details>

      <div
        id="games"
        phx-update="stream"
        class="grid gap-6 sm:grid-cols-2 lg:grid-cols-3"
      >
        <div
          id="games-empty"
          class="hidden only:block col-span-full rounded-2xl border border-dashed border-base-300 p-12 text-center text-base-content/60"
        >
          No games yet.
          <.link
            :if={admin?(@current_scope)}
            navigate={~p"/admin/games"}
            class="text-primary underline"
          >
            Add the first one
          </.link>
        </div>
        <.link
          :for={{id, card} <- @streams.games}
          id={id}
          navigate={~p"/games/#{card.game.slug}"}
          class="group flex flex-col overflow-hidden rounded-2xl border border-base-300 bg-base-200/50 transition duration-300 hover:-translate-y-1 hover:border-primary/60 hover:shadow-xl hover:shadow-primary/10"
        >
          <div class="relative aspect-[16/10] overflow-hidden bg-gradient-to-br from-primary/30 to-accent/30">
            <img
              :if={image_url(card.game)}
              src={image_url(card.game)}
              alt=""
              loading="lazy"
              class="size-full object-cover transition duration-500 group-hover:scale-105"
              style={"filter: grayscale(#{100 - round(card.pct)}%)"}
            />
            <div :if={!image_url(card.game)} class="flex size-full items-center justify-center">
              <.icon name="hero-puzzle-piece" class="size-16 text-base-content/30" />
            </div>
            <span class="absolute right-3 top-3 rounded-full bg-base-100/90 px-2.5 py-1 text-xs font-semibold shadow">
              {percent(card.pct)}
            </span>
          </div>
          <div class="flex flex-1 flex-col gap-3 p-5">
            <h2 class="text-lg font-semibold tracking-tight">{card.game.name}</h2>
            <.progress_bar value={card.pct} />
            <dl class="mt-auto grid grid-cols-3 gap-2 text-center text-xs">
              <div>
                <dt class="text-base-content/60">Solved</dt>
                <dd class="text-base font-semibold">{number(card.totals.solved.count)}</dd>
              </div>
              <div>
                <dt class="text-base-content/60">Claimed</dt>
                <dd class="text-base font-semibold">{number(card.totals.claimed.count)}</dd>
              </div>
              <div>
                <dt class="text-base-content/60">Remaining</dt>
                <dd class="text-base font-semibold">{number(card.totals.remaining.count)}</dd>
              </div>
            </dl>
          </div>
        </.link>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    games = Decomp.list_games()

    if connected?(socket),
      do: Enum.each(games, &Phoenix.PubSub.subscribe(Dcomp.PubSub, Sync.topic(&1.slug)))

    {:ok,
     socket
     |> assign(:page_title, "Games")
     |> stream(:games, Enum.map(games, &card/1))}
  end

  @impl true
  def handle_info({:synced, slug}, socket) do
    case Decomp.get_game_by_slug(slug) do
      nil -> {:noreply, socket}
      game -> {:noreply, stream_insert(socket, :games, card(game))}
    end
  end

  defp card(game) do
    totals = Metrics.totals(game)
    %{id: game.id, game: game, totals: totals, pct: pct(totals)}
  end

  defp pct(%{all: %{bytes: 0}}), do: 0.0
  defp pct(%{solved: s, all: a}), do: Float.round(s.bytes * 100 / a.bytes, 1)

  defp admin?(%{user: user}), do: Dcomp.Accounts.User.admin?(user)
  defp admin?(_), do: false
end
