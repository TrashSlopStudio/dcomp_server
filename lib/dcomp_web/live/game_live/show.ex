defmodule DcompWeb.GameLive.Show do
  @moduledoc """
  One game: the puzzle, ranking and metrics.

  The puzzle and burn-up chart are drawn client-side. Their data is not in the page: each hook asks
  for it with a `*-ready` event once mounted (so it can never arrive before the hook is listening)
  and the server pushes fresh data after every sync.
  """
  use DcompWeb, :live_view

  import DcompWeb.GameComponents

  alias Dcomp.Decomp
  alias Dcomp.Decomp.{Metrics, Sync}

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    game = Decomp.get_game_by_slug!(slug)
    if connected?(socket), do: Phoenix.PubSub.subscribe(Dcomp.PubSub, Sync.topic(slug))

    {:ok, socket |> assign(page_title: game.name, game: game) |> load()}
  end

  @impl true
  def handle_event("puzzle-ready", _params, socket), do: {:reply, puzzle_payload(socket), socket}
  def handle_event("burnup-ready", _params, socket), do: {:reply, burn_up_payload(socket), socket}

  @impl true
  def handle_info({:synced, _slug}, socket) do
    socket = load(socket)

    {:noreply,
     socket
     |> push_event("puzzle:data", puzzle_payload(socket))
     |> push_event("burnup:data", burn_up_payload(socket))}
  end

  # Loads everything the page shows. Small lists are streams reset on each refresh.
  defp load(socket) do
    game = Decomp.get_game!(socket.assigns.game.id)
    m = Metrics.for_game(game)

    socket
    |> assign(
      game: game,
      layout_mode: Decomp.get_settings().layout_mode,
      m: m,
      now: DateTime.utc_now()
    )
    |> stream(:leaderboard, m.leaderboard, reset: true)
    |> stream(:claims, m.active_claims, reset: true)
    |> stream(:remaining, m.top_remaining, reset: true)
    |> stream(:strikes, m.strikes, reset: true)
    |> stream(:activity, m.recent_activity, reset: true)
  end

  defp puzzle_payload(%{assigns: %{game: game, layout_mode: mode}}) do
    {pieces, people} = Metrics.puzzle_pieces(game)

    %{
      pieces: pieces,
      people: people,
      mode: Atom.to_string(mode),
      image: image_url(game),
      name: game.name
    }
  end

  # [[unix_ms, solved_count, solved_bytes], ...]
  defp burn_up_payload(%{assigns: %{m: m}}) do
    %{
      points:
        for p <- m.burn_up do
          [
            p.date |> DateTime.new!(~T[00:00:00], "Etc/UTC") |> DateTime.to_unix(:millisecond),
            p.count,
            p.bytes
          ]
        end
    }
  end

  defp max_bucket(dist), do: dist |> Enum.map(& &1.count) |> Enum.max(fn -> 1 end) |> max(1)

  # "https://github.com/owner/repo(.git)" -> "owner/repo"; nil for other hosts.
  defp repo_slug(%{repo_url: url}) do
    case Regex.run(~r{^https://github\.com/([^/\s]+/[^/\s]+?)(?:\.git)?/?$}, url) do
      [_, slug] -> slug
      _ -> nil
    end
  end

  defp clone_command(game) do
    case repo_slug(game) do
      nil -> "git clone #{game.repo_url}"
      slug -> "gh repo fork --clone #{slug}"
    end
  end

  defp rules(game) do
    [
      game.max_claims && "up to #{game.max_claims} claims at once",
      game.claim_hours && "claims expire after #{game.claim_hours} h",
      game.max_strikes && "#{game.max_strikes} strikes and you can't claim"
    ]
    |> Enum.filter(& &1)
    |> case do
      [] -> "Release what you won't finish: expired claims earn strikes."
      list -> "Rules here: " <> Enum.join(list, ", ") <> ". Release what you won't finish."
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} wide>
      <div class="space-y-1">
        <.link
          navigate={~p"/"}
          id="back-to-games"
          class="inline-flex items-center gap-1 text-sm text-base-content/60 transition hover:text-primary"
        >
          <.icon name="hero-arrow-left" class="size-4" /> All games
        </.link>
        <div class="flex flex-wrap items-end justify-between gap-3">
          <h1 id="game-title" class="text-3xl font-bold tracking-tight">{@game.name}</h1>
          <div class="flex flex-wrap items-center gap-3 text-sm text-base-content/60">
            <a
              href={@game.repo_url}
              target="_blank"
              rel="noopener noreferrer"
              id="repo-link"
              class="inline-flex items-center gap-1 transition hover:text-primary"
            >
              <.icon name="hero-code-bracket" class="size-4" /> Repository
            </a>
            <span id="last-synced" class="inline-flex items-center gap-1">
              <.icon name="hero-arrow-path" class="size-4" />
              Synced {time_ago(@game.last_synced_at, @now)}
            </span>
          </div>
        </div>
      </div>

      <div
        :if={@game.last_sync_error}
        id="sync-error"
        role="alert"
        class="flex items-start gap-2 rounded-xl border border-warning/50 bg-warning/10 px-4 py-3 text-sm"
      >
        <.icon name="hero-exclamation-triangle" class="mt-0.5 size-4 shrink-0 text-warning" />
        <span>The last sync failed, so this data may be out of date.</span>
      </div>

      <div class="grid gap-6 lg:grid-cols-3">
        <.panel id="puzzle-panel" title="The puzzle" class="lg:col-span-2">
          <:aside>
            <span class="text-xs text-base-content/60">
              {if @layout_mode == :size, do: "Pieces sized by function size", else: "Equal pieces"}
            </span>
          </:aside>
          <div
            id="puzzle"
            phx-hook=".Puzzle"
            phx-update="ignore"
            class="relative w-full overflow-visible"
          >
            <canvas
              id="puzzle-canvas"
              class="block w-full rounded-xl"
              aria-label={"#{@game.name} puzzle"}
            ></canvas>
            <div
              id="puzzle-tip"
              class="pointer-events-none absolute z-20 hidden max-w-60 space-y-1 rounded-lg border border-base-300 bg-base-100 px-3 py-2 text-xs shadow-xl"
            >
            </div>
          </div>
          <ul
            id="puzzle-legend"
            class="mt-3 flex flex-wrap gap-x-5 gap-y-1 text-xs text-base-content/70"
          >
            <li class="flex items-center gap-1.5">
              <span class="size-3 rounded-sm bg-base-300"></span> Unclaimed
            </li>
            <li class="flex items-center gap-1.5">
              <span class="size-3 rounded-sm bg-warning/60"></span> Claimed
            </li>
            <li class="flex items-center gap-1.5">
              <span class="size-3 rounded-sm bg-primary"></span> Solved (shows the picture)
            </li>
          </ul>
        </.panel>

        <div class="flex flex-col gap-6">
          <div
            id="completion"
            class="rounded-2xl border border-base-300 bg-gradient-to-br from-primary/15 to-transparent p-6"
          >
            <div class="text-xs font-semibold uppercase tracking-wide text-base-content/60">
              Complete
            </div>
            <div class="mt-1 text-6xl font-bold tracking-tight">{percent(@m.completion_pct)}</div>
            <.progress_bar value={@m.completion_pct} class="mt-4" />
            <div class="mt-2 text-xs text-base-content/60">
              by bytes · {percent(@m.completion_pct_count)} by function count
            </div>
          </div>
          <div class="grid grid-cols-2 gap-3">
            <.stat
              id="stat-solved"
              icon="hero-check-circle"
              label="Solved"
              value={number(@m.totals.solved.count)}
              sub={bytes(@m.totals.solved.bytes)}
            />
            <.stat
              id="stat-claimed"
              icon="hero-hand-raised"
              label="Claimed"
              value={number(@m.totals.claimed.count)}
              sub={bytes(@m.totals.claimed.bytes)}
            />
            <.stat
              id="stat-unclaimed"
              icon="hero-squares-2x2"
              label="Unclaimed"
              value={number(@m.totals.unclaimed.count)}
              sub={bytes(@m.totals.unclaimed.bytes)}
            />
            <.stat
              id="stat-remaining"
              icon="hero-flag"
              label="Remaining"
              value={number(@m.totals.remaining.count)}
              sub={"of #{number(@m.totals.all.count)} total"}
            />
          </div>
          <details
            id="contribute"
            class="group rounded-2xl border border-base-300 bg-base-200/50 px-4 py-3 text-sm"
          >
            <summary class="flex cursor-pointer list-none items-center justify-between gap-2 font-semibold">
              <span class="flex items-center gap-2">
                <.icon name="hero-command-line" class="size-4 text-primary" /> How to contribute
              </span>
              <.icon
                name="hero-chevron-down"
                class="size-4 text-base-content/60 transition group-open:rotate-180"
              />
            </summary>
            <ol class="mt-3 list-decimal space-y-3 pl-5 text-base-content/80">
              <li>
                Fork and clone <a
                  href={@game.repo_url}
                  target="_blank"
                  rel="noopener noreferrer"
                  class="text-primary underline"
                >
                  {repo_slug(@game) || @game.repo_url}
                </a>:
                <code
                  id="contribute-clone"
                  class="mt-1 block break-all rounded bg-base-300 px-2 py-1.5"
                >
                  {clone_command(@game)}
                </code>
              </li>
              <li>
                Follow the setup in <code class="rounded bg-base-300 px-1.5 py-0.5">AGENTS.md</code>
                (compiler tools and your own legally obtained ROM as <code class="rounded bg-base-300 px-1.5 py-0.5">baserom.gba</code>).
              </li>
              <li>
                Run <code class="rounded bg-base-300 px-1.5 py-0.5">claude</code>
                in the clone and tell it:
                <p class="mt-2 rounded-lg bg-base-300/60 p-3 italic">
                  "Follow AGENTS.md and contribute to this decomp: claim a function, match it, and open the pull requests against the {@game.branch} branch."
                </p>
              </li>
            </ol>
            <p id="contribute-rules" class="mt-3 text-xs text-base-content/60">
              {rules(@game)}
            </p>
          </details>
        </div>
      </div>

      <div class="grid grid-cols-2 gap-3 sm:grid-cols-4 lg:grid-cols-6">
        <.stat
          id="stat-pace"
          icon="hero-bolt"
          label="Pace"
          value={"#{Float.round(@m.velocity.solves_per_day, 1)}/day"}
          sub={"#{@m.velocity.solves_7d} solved in 7 days"}
        />
        <.stat
          id="stat-eta"
          icon="hero-calendar-days"
          label="Est. finish"
          value={eta(@m.velocity.eta_days)}
          sub="at the 30-day pace"
        />
        <.stat
          id="stat-median"
          icon="hero-clock"
          label="Claim to solve"
          value={duration(@m.median_claim_to_solve_s)}
          sub="median"
        />
        <.stat
          id="stat-conversion"
          icon="hero-arrow-trending-up"
          label="Claims solved"
          value={if @m.conversion_rate, do: percent(@m.conversion_rate * 100), else: "–"}
          sub="of all claims"
        />
        <.stat
          id="stat-expired"
          icon="hero-clock"
          label="Expired"
          value={number(@m.expired)}
          sub="claims timed out"
        />
        <.stat
          id="stat-released"
          icon="hero-arrow-uturn-left"
          label="Released"
          value={number(@m.released)}
          sub="given back"
        />
      </div>

      <.panel id="burn-up-panel" title="Functions solved over time">
        <div
          id="burn-up"
          phx-hook=".BurnUp"
          phx-update="ignore"
          class="relative w-full text-base-content"
        >
        </div>
        <details class="mt-3 text-xs text-base-content/70">
          <summary class="cursor-pointer select-none hover:text-primary">View as table</summary>
          <table id="burn-up-table" class="mt-2 w-full text-left">
            <thead>
              <tr class="text-base-content/50">
                <th class="py-1 font-medium">Date</th>
                <th class="py-1 text-right font-medium">Solved (total)</th>
                <th class="py-1 text-right font-medium">Bytes</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={p <- @m.burn_up} class="border-t border-base-300">
                <td class="py-1">{Date.to_iso8601(p.date)}</td>
                <td class="py-1 text-right tabular-nums">{number(p.count)}</td>
                <td class="py-1 text-right tabular-nums">{number(p.bytes)}</td>
              </tr>
            </tbody>
          </table>
        </details>
      </.panel>

      <div class="grid gap-6 lg:grid-cols-2">
        <.panel id="leaderboard-panel" title="Ranking">
          <ol
            id="leaderboard"
            phx-update="stream"
            class="divide-y divide-base-300 [counter-reset:rank]"
          >
            <li
              id="leaderboard-empty"
              class="hidden py-6 text-center text-sm text-base-content/60 only:block"
            >
              Nobody has solved a function yet.
            </li>
            <li
              :for={{id, row} <- @streams.leaderboard}
              id={id}
              class="flex items-center gap-3 py-2.5 text-sm [counter-increment:rank] before:w-6 before:text-center before:text-xs before:font-semibold before:text-base-content/50 before:content-[counter(rank)]"
            >
              <.person login={row.login} url={row.avatar_url} size="size-7" />
              <span class="ml-auto text-right tabular-nums">
                <span class="font-semibold">{number(row.solves)}</span>
                <span class="text-base-content/50"> · {bytes(row.bytes)}</span>
              </span>
            </li>
          </ol>
        </.panel>

        <.panel id="claims-panel" title="Active claims">
          <ul id="claims" phx-update="stream" class="divide-y divide-base-300">
            <li
              id="claims-empty"
              class="hidden py-6 text-center text-sm text-base-content/60 only:block"
            >
              No open claims.
            </li>
            <li
              :for={{id, c} <- @streams.claims}
              id={id}
              class="flex items-center gap-3 py-2.5 text-sm"
            >
              <.person login={c.login} url={c.avatar_url} />
              <span class="ml-auto flex items-center gap-3 text-right">
                <span class="font-mono text-xs text-base-content/60">{c.addr}</span>
                <span class={[
                  "w-20 text-xs",
                  if(c.stale?, do: "font-semibold text-warning", else: "text-base-content/60")
                ]}>
                  <.icon :if={c.stale?} name="hero-exclamation-triangle" class="mr-0.5 size-3.5" />
                  {time_left(c.expires_at, @now)}
                </span>
              </span>
            </li>
          </ul>
        </.panel>

        <.panel id="remaining-panel" title="Biggest functions left">
          <ul id="remaining" phx-update="stream" class="divide-y divide-base-300">
            <li
              id="remaining-empty"
              class="hidden py-6 text-center text-sm text-base-content/60 only:block"
            >
              Everything is solved.
            </li>
            <li
              :for={{id, f} <- @streams.remaining}
              id={id}
              class="flex items-center gap-3 py-2 text-sm"
            >
              <span class="font-mono text-xs">{f.addr}</span>
              <span class="ml-auto tabular-nums text-base-content/70">{bytes(f.size)}</span>
              <span class={[
                "w-20 rounded-full px-2 py-0.5 text-center text-xs",
                if(f.status == :claimed,
                  do: "bg-warning/20 text-warning",
                  else: "bg-base-300 text-base-content/70"
                )
              ]}>
                {f.status}
              </span>
            </li>
          </ul>
        </.panel>

        <.panel id="sizes-panel" title="Unsolved by size">
          <ul id="sizes" class="space-y-2.5">
            <li
              :for={b <- @m.size_distribution}
              class="grid grid-cols-[6rem_1fr_3.5rem] items-center gap-3 text-xs"
            >
              <span class="text-base-content/70">{b.label}</span>
              <span class="h-2 overflow-hidden rounded-full bg-base-300">
                <span
                  class="block h-full rounded-full bg-primary"
                  style={"width: #{b.count * 100 / max_bucket(@m.size_distribution)}%"}
                ></span>
              </span>
              <span class="text-right tabular-nums">{number(b.count)}</span>
            </li>
          </ul>
        </.panel>

        <.panel id="activity-panel" title="Recent activity">
          <ul id="activity" phx-update="stream" class="divide-y divide-base-300">
            <li
              id="activity-empty"
              class="hidden py-6 text-center text-sm text-base-content/60 only:block"
            >
              Nothing has happened yet.
            </li>
            <li
              :for={{id, e} <- @streams.activity}
              id={id}
              class="flex items-center gap-3 py-2.5 text-sm"
            >
              <.icon name={event_icon(e.type)} class="size-4 shrink-0 text-base-content/50" />
              <.person login={e.login} url={e.avatar_url} size="size-5" />
              <span class="text-base-content/70">
                {event_label(e.type)} <span class="font-mono text-xs">{e.addr}</span>
              </span>
              <span class="ml-auto whitespace-nowrap text-xs text-base-content/50">{time_ago(
                e.at,
                @now
              )}</span>
            </li>
          </ul>
        </.panel>

        <.panel id="strikes-panel" title="Strikes">
          <ul id="strikes" phx-update="stream" class="divide-y divide-base-300">
            <li
              id="strikes-empty"
              class="hidden py-6 text-center text-sm text-base-content/60 only:block"
            >
              No expired claims.
            </li>
            <li
              :for={{id, s} <- @streams.strikes}
              id={id}
              class="flex items-center gap-3 py-2.5 text-sm"
            >
              <.person login={s.login} url={s.avatar_url} />
              <span class="ml-auto flex items-center gap-2">
                <span
                  :if={s.banned?}
                  class="rounded-full bg-error/15 px-2 py-0.5 text-xs font-medium text-error"
                >
                  can't claim
                </span>
                <span class="tabular-nums text-base-content/70">
                  {s.count}{if @game.max_strikes, do: " / #{@game.max_strikes}"}
                </span>
              </span>
            </li>
          </ul>
        </.panel>
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".Puzzle">
        // Draws every function as a piece of the game's picture: grey when unclaimed, tinted when
        // claimed, showing its slice of the picture when solved.
        const NAMES = ["Unclaimed", "Claimed", "Solved"]

        // Squarified treemap: [{i, v}] sorted by v desc -> [{i, x, y, w, h}] filling w x h.
        function squarify(items, x, y, w, h) {
          const total = items.reduce((s, e) => s + e.v, 0)
          const k = (w * h) / total
          const q = items.map(e => ({i: e.i, a: e.v * k}))
          const out = []
          let row = []
          const sum = r => r.reduce((t, e) => t + e.a, 0)
          const worst = (r, side) => {
            const t = sum(r)
            let mx = 0, mn = Infinity
            for (const e of r) { if (e.a > mx) mx = e.a; if (e.a < mn) mn = e.a }
            return Math.max((side * side * mx) / (t * t), (t * t) / (side * side * mn))
          }
          const place = () => {
            const t = sum(row)
            let o = 0
            if (w >= h) {
              const cw = t / h
              for (const e of row) { const eh = e.a / cw; out.push({i: e.i, x, y: y + o, w: cw, h: eh}); o += eh }
              x += cw; w -= cw
            } else {
              const rh = t / w
              for (const e of row) { const ew = e.a / rh; out.push({i: e.i, x: x + o, y, w: ew, h: rh}); o += ew }
              y += rh; h -= rh
            }
            row = []
          }
          while (q.length) {
            const side = Math.min(w, h)
            if (!row.length || worst([...row, q[0]], side) <= worst(row, side)) row.push(q.shift())
            else place()
          }
          if (row.length) place()
          return out
        }

        export default {
          mounted() {
            this.canvas = this.el.querySelector("canvas")
            this.tip = this.el.querySelector("#puzzle-tip")
            this.ctx = this.canvas.getContext("2d")
            this.pieces = []
            this.people = []
            this.rects = []
            this.hover = null
            this.img = null
            this.imgUrl = undefined
            this.w = 0
            this.h = 0

            this.canvas.addEventListener("mousemove", e => this.onMove(e))
            this.canvas.addEventListener("mouseleave", () => this.setHover(null))
            this.ro = new ResizeObserver(() => this.layout())
            this.ro.observe(this.el)
            this.theme = new MutationObserver(() => this.draw())
            this.theme.observe(document.documentElement, {attributes: true, attributeFilter: ["data-theme"]})

            this.handleEvent("puzzle:data", d => this.setData(d))
            this.pushEvent("puzzle-ready", {}, d => this.setData(d))
          },

          destroyed() {
            this.ro && this.ro.disconnect()
            this.theme && this.theme.disconnect()
          },

          setData(d) {
            this.pieces = d.pieces
            this.people = d.people
            this.mode = d.mode
            this.name = d.name
            if (d.image === this.imgUrl && this.img) return this.layout()
            this.imgUrl = d.image
            this.img = this.placeholder()
            this.layout()
            if (d.image) {
              const img = new Image()
              img.onload = () => { if (this.imgUrl === d.image) { this.img = img; this.layout() } }
              img.src = d.image
            }
          },

          // Used until (or instead of) the game's own picture.
          placeholder() {
            const c = document.createElement("canvas")
            c.width = 1280; c.height = 800
            const g = c.getContext("2d")
            const bg = g.createLinearGradient(0, 0, 1280, 800)
            bg.addColorStop(0, "#ff7a18"); bg.addColorStop(0.5, "#e91e63"); bg.addColorStop(1, "#3b2dbf")
            g.fillStyle = bg; g.fillRect(0, 0, 1280, 800)
            g.fillStyle = "#fff"; g.textAlign = "center"; g.textBaseline = "middle"
            g.font = "bold 120px system-ui, sans-serif"
            g.fillText(this.name || "", 640, 400, 1160)
            return c
          },

          layout() {
            if (!this.img || !this.pieces.length) return
            const w = this.el.clientWidth
            if (!w) return
            const h = Math.round((w * this.img.height) / this.img.width)
            const dpr = window.devicePixelRatio || 1
            this.w = w; this.h = h
            this.canvas.width = Math.round(w * dpr); this.canvas.height = Math.round(h * dpr)
            this.canvas.style.height = h + "px"

            let items = this.pieces.map((p, i) => ({i, v: this.mode === "size" ? Math.max(p[1], 1) : 1}))
            if (this.mode === "size") items.sort((a, b) => b.v - a.v)
            this.rects = squarify(items, 0, 0, w, h)
            this.draw()
          },

          colors() {
            const cs = getComputedStyle(this.el)
            const v = (n, fb) => cs.getPropertyValue(n).trim() || fb
            return {
              surface: v("--color-base-100", "#111"),
              unclaimed: v("--color-base-300", "#2a2e3a"),
              claimed: v("--color-warning", "#d4a72c"),
              ring: v("--color-base-content", "#fff"),
            }
          },

          draw() {
            if (!this.rects.length) return
            const ctx = this.ctx, dpr = window.devicePixelRatio || 1
            const c = this.colors()
            ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
            ctx.fillStyle = c.surface
            ctx.fillRect(0, 0, this.w, this.h)
            const sx = this.img.width / this.w, sy = this.img.height / this.h

            for (const r of this.rects) {
              const status = this.pieces[r.i][2]
              if (status === 2) {
                ctx.drawImage(this.img, r.x * sx, r.y * sy, r.w * sx, r.h * sy, r.x, r.y, r.w, r.h)
              } else {
                ctx.fillStyle = c.unclaimed
                ctx.fillRect(r.x, r.y, r.w, r.h)
                if (status === 1) {
                  ctx.globalAlpha = 0.6
                  ctx.fillStyle = c.claimed
                  ctx.fillRect(r.x, r.y, r.w, r.h)
                  ctx.globalAlpha = 1
                }
              }
              if (r.w > 4 && r.h > 4) {
                ctx.strokeStyle = c.surface
                ctx.lineWidth = 1
                ctx.strokeRect(r.x + 0.5, r.y + 0.5, r.w - 1, r.h - 1)
              }
            }

            if (this.hover) {
              const r = this.hover
              ctx.strokeStyle = c.ring
              ctx.lineWidth = 2
              ctx.strokeRect(r.x + 1, r.y + 1, Math.max(r.w - 2, 1), Math.max(r.h - 2, 1))
            }
          },

          onMove(e) {
            const b = this.canvas.getBoundingClientRect()
            const x = e.clientX - b.left, y = e.clientY - b.top
            const r = this.rects.find(r => x >= r.x && x < r.x + r.w && y >= r.y && y < r.y + r.h) || null
            this.setHover(r, x, y)
          },

          setHover(r, x, y) {
            const changed = r !== this.hover
            this.hover = r
            if (!r) { this.tip.classList.add("hidden"); if (changed) this.draw(); return }
            if (changed) { this.fillTip(this.pieces[r.i]); this.draw() }
            this.tip.classList.remove("hidden")
            const tw = this.tip.offsetWidth
            this.tip.style.left = (x + 16 + tw > this.w ? x - 16 - tw : x + 16) + "px"
            this.tip.style.top = y + 16 + "px"
          },

          // Built with DOM calls, never innerHTML: logins come from repo files.
          fillTip(p) {
            const [addr, size, status, who] = p
            const line = (text, cls) => {
              const d = document.createElement("div")
              d.textContent = text
              if (cls) d.className = cls
              this.tip.appendChild(d)
            }
            this.tip.replaceChildren()
            line("func_" + addr, "font-mono font-semibold")
            line(size + " bytes · " + NAMES[status], "text-base-content/70")
            if (who != null) {
              const person = this.people[who]
              const row = document.createElement("div")
              row.className = "flex items-center gap-1.5 pt-0.5"
              const img = document.createElement("img")
              img.src = person.avatar
              img.alt = ""
              img.className = "size-5 rounded-full bg-base-300"
              const name = document.createElement("span")
              name.textContent = (status === 2 ? "Solved by " : "Claimed by ") + person.login
              row.append(img, name)
              this.tip.appendChild(row)
            } else if (status === 2) {
              line("Solved by an unknown contributor", "text-base-content/70")
            }
          },
        }
      </script>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".BurnUp">
        // Cumulative functions solved per day. One series, so no legend: the panel title names it.
        const NS = "http://www.w3.org/2000/svg"
        const HEIGHT = 220
        const M = {l: 40, r: 44, t: 14, b: 26}

        const svg = (tag, attrs, parent) => {
          const el = document.createElementNS(NS, tag)
          for (const [k, v] of Object.entries(attrs)) el.setAttribute(k, v)
          if (parent) parent.appendChild(el)
          return el
        }

        const niceMax = v => {
          const p = Math.pow(10, Math.floor(Math.log10(Math.max(v, 1))))
          return [1, 2, 5, 10].map(m => m * p).find(n => n >= v) || 10 * p
        }

        const day = ms => new Date(ms).toISOString().slice(0, 10)

        export default {
          mounted() {
            this.points = []
            this.tip = document.createElement("div")
            this.tip.className =
              "pointer-events-none absolute z-20 hidden whitespace-nowrap rounded-lg border border-base-300 bg-base-100 px-3 py-2 text-xs shadow-xl"
            this.ro = new ResizeObserver(() => this.render())
            this.ro.observe(this.el)
            this.handleEvent("burnup:data", d => this.setData(d))
            this.pushEvent("burnup-ready", {}, d => this.setData(d))
          },

          destroyed() { this.ro && this.ro.disconnect() },

          setData(d) { this.points = d.points; this.render() },

          render() {
            const W = this.el.clientWidth
            if (!W) return
            this.el.replaceChildren()
            if (!this.points.length) {
              const p = document.createElement("p")
              p.className = "py-10 text-center text-sm text-base-content/60"
              p.textContent = "No solves yet."
              this.el.appendChild(p)
              return
            }

            // Cumulative: start from zero the day before the first solve so it reads as a climb.
            const pts = [[this.points[0][0] - 86400000, 0, 0], ...this.points]
            const t0 = pts[0][0], t1 = pts[pts.length - 1][0]
            const ymax = niceMax(pts[pts.length - 1][1])
            const iw = W - M.l - M.r, ih = HEIGHT - M.t - M.b
            const X = t => M.l + (t1 === t0 ? iw / 2 : ((t - t0) / (t1 - t0)) * iw)
            const Y = v => M.t + ih - (v / ymax) * ih

            const root = svg("svg", {width: W, height: HEIGHT, viewBox: `0 0 ${W} ${HEIGHT}`, role: "img", "aria-label": "Functions solved over time"})
            const muted = {fill: "currentColor", "fill-opacity": 0.6, "font-size": 11}

            for (let i = 0; i <= 4; i++) {
              const v = (ymax / 4) * i, y = Y(v)
              svg("line", {x1: M.l, x2: W - M.r, y1: y, y2: y, stroke: "currentColor", "stroke-opacity": 0.12, "stroke-width": 1}, root)
              svg("text", {...muted, x: M.l - 8, y: y + 4, "text-anchor": "end"}, root).textContent = Math.round(v)
            }
            svg("text", {...muted, x: M.l, y: HEIGHT - 6, "text-anchor": "start"}, root).textContent = day(t0)
            if (t1 !== t0) svg("text", {...muted, x: W - M.r, y: HEIGHT - 6, "text-anchor": "end"}, root).textContent = day(t1)

            const line = pts.map((p, i) => `${i ? "L" : "M"}${X(p[0])},${Y(p[1])}`).join("")
            const base = Y(0)
            svg("path", {d: `${line}L${X(t1)},${base}L${X(t0)},${base}Z`, style: "fill: var(--color-primary); fill-opacity: 0.1"}, root)
            svg("path", {d: line, fill: "none", "stroke-width": 2, "stroke-linejoin": "round", "stroke-linecap": "round", style: "stroke: var(--color-primary)"}, root)

            const last = pts[pts.length - 1]
            svg("circle", {cx: X(last[0]), cy: Y(last[1]), r: 4, "stroke-width": 2, style: "fill: var(--color-primary); stroke: var(--color-base-200)"}, root)
            svg("text", {x: X(last[0]) + 10, y: Y(last[1]) + 4, "font-size": 12, "font-weight": 600, fill: "currentColor"}, root).textContent = last[1]

            const cross = svg("line", {y1: M.t, y2: base, stroke: "currentColor", "stroke-opacity": 0.35, "stroke-width": 1, visibility: "hidden"}, root)
            const dot = svg("circle", {r: 4, "stroke-width": 2, visibility: "hidden", style: "fill: var(--color-primary); stroke: var(--color-base-200)"}, root)
            const hit = svg("rect", {x: M.l - 10, y: 0, width: iw + 20, height: HEIGHT, fill: "transparent"}, root)

            hit.addEventListener("mousemove", e => {
              const px = e.clientX - root.getBoundingClientRect().left
              let best = pts[0]
              for (const p of pts) if (Math.abs(X(p[0]) - px) < Math.abs(X(best[0]) - px)) best = p
              const x = X(best[0]), y = Y(best[1])
              cross.setAttribute("x1", x); cross.setAttribute("x2", x); cross.setAttribute("visibility", "visible")
              dot.setAttribute("cx", x); dot.setAttribute("cy", y); dot.setAttribute("visibility", "visible")
              this.tip.replaceChildren()
              const d = document.createElement("div"); d.className = "font-semibold"; d.textContent = day(best[0])
              const n = document.createElement("div"); n.textContent = best[1] + " functions solved"
              const b = document.createElement("div"); b.className = "text-base-content/60"; b.textContent = best[2] + " bytes"
              this.tip.append(d, n, b)
              this.tip.classList.remove("hidden")
              const tw = this.tip.offsetWidth
              this.tip.style.left = (x + 14 + tw > W ? x - 14 - tw : x + 14) + "px"
              this.tip.style.top = Math.max(y - 20, 0) + "px"
            })
            hit.addEventListener("mouseleave", () => {
              cross.setAttribute("visibility", "hidden"); dot.setAttribute("visibility", "hidden")
              this.tip.classList.add("hidden")
            })

            this.el.append(root, this.tip)
          },
        }
      </script>
    </Layouts.app>
    """
  end
end
