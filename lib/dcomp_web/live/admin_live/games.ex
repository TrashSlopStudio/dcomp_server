defmodule DcompWeb.AdminLive.Games do
  @moduledoc "Admin: add, edit, sync and remove games."
  use DcompWeb, :live_view

  import DcompWeb.GameComponents

  alias Dcomp.Decomp
  alias Dcomp.Decomp.{Game, Syncer, Uploads}

  @max_image_bytes 5_000_000

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Games · Admin")
     |> allow_upload(:image,
       accept: Uploads.exts(),
       max_entries: 1,
       max_file_size: @max_image_bytes
     )
     |> stream(:games, Decomp.list_games())}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params), do: assign(socket, game: nil, form: nil)

  defp apply_action(socket, :new, _params) do
    game = %Game{}
    assign(socket, game: game, form: to_form(Decomp.change_game(game)))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    game = Decomp.get_game!(id)
    assign(socket, game: game, form: to_form(Decomp.change_game(game)))
  end

  @impl true
  def handle_event("validate", %{"game" => params}, socket) do
    form = socket.assigns.game |> Decomp.change_game(params) |> to_form(action: :validate)
    {:noreply, assign(socket, form: form)}
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :image, ref)}
  end

  def handle_event("save", %{"game" => params}, socket) do
    save(socket, socket.assigns.live_action, params)
  end

  def handle_event("sync", %{"id" => id}, socket) do
    case Decomp.get_game(id) do
      nil ->
        {:noreply, gone(socket, id)}

      game ->
        Syncer.nudge(game.slug)
        {:noreply, put_flash(socket, :info, "Sync queued for #{game.name}.")}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    case Decomp.get_game(id) do
      nil ->
        {:noreply, gone(socket, id)}

      game ->
        {:ok, _} = Decomp.delete_game(game)
        Uploads.delete(game.image_path)

        {:noreply,
         socket |> stream_delete(:games, game) |> put_flash(:info, "#{game.name} deleted.")}
    end
  end

  # Deleted in another tab since this page loaded.
  defp gone(socket, id) do
    socket
    |> stream_delete_by_dom_id(:games, "games-#{id}")
    |> put_flash(:error, "That game no longer exists.")
  end

  defp save(socket, :new, params) do
    case Decomp.create_game(params) do
      {:ok, game} ->
        Syncer.nudge(game.slug)
        finish(socket, game, "#{game.name} added. First sync is running.")

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save(socket, :edit, params) do
    case Decomp.update_game(socket.assigns.game, params) do
      {:ok, game} -> finish(socket, game, "#{game.name} updated.")
      {:error, changeset} -> {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  # Stores the uploaded image (if any), then returns to the list.
  defp finish(socket, game, message) do
    results =
      consume_uploaded_entries(socket, :image, fn %{path: path}, entry ->
        {:ok, Uploads.save(path, entry.client_name)}
      end)

    case results do
      [{:ok, name}] ->
        old = game.image_path
        {:ok, game} = Decomp.set_game_image(game, name)
        if old, do: Uploads.delete(old)
        done(socket, game, message)

      [{:error, :bad_type}] ->
        done(
          socket,
          game,
          message <> " The image was rejected: it isn't a real PNG, JPEG or WebP."
        )

      [] ->
        done(socket, game, message)
    end
  end

  defp done(socket, game, message) do
    {:noreply,
     socket
     |> stream_insert(:games, game)
     |> put_flash(:info, message)
     |> push_navigate(to: ~p"/admin/games")}
  end

  defp upload_error(:too_large), do: "That file is larger than 5 MB."
  defp upload_error(:not_accepted), do: "Use a PNG, JPEG or WebP image."
  defp upload_error(:too_many_files), do: "Only one image."
  defp upload_error(_), do: "Upload failed."

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} wide>
      <.admin_tabs active={:games} />

      <%= if @form do %>
        <.panel
          id="game-form-panel"
          title={if @live_action == :new, do: "Add a game", else: "Edit #{@game.name}"}
        >
          <.form for={@form} id="game-form" phx-change="validate" phx-submit="save" class="space-y-2">
            <.input field={@form[:name]} type="text" label="Name" placeholder="Drill Dozer" required />
            <.input
              field={@form[:repo_url]}
              type="text"
              label="Repository URL"
              placeholder="https://github.com/owner/repo"
              required
            />
            <div class="grid gap-4 sm:grid-cols-2">
              <.input field={@form[:branch]} type="text" label="Branch" />
              <.input
                field={@form[:slug]}
                type="text"
                label={if @live_action == :edit, do: "Slug (fixed)", else: "Slug (optional)"}
                placeholder="drill-dozer"
                disabled={@live_action == :edit}
              />
            </div>
            <.input
              field={@form[:rom_sha1]}
              type="text"
              label="Expected ROM SHA1 (optional)"
              placeholder="40 hex characters, shown to contributors to verify their own dump"
            />

            <div class="fieldset mb-2">
              <span class="label mb-1">Puzzle image (PNG, JPEG or WebP, up to 5 MB)</span>
              <div
                :if={@game.image_path}
                class="mb-2 flex items-center gap-3 text-xs text-base-content/60"
              >
                <img src={image_url(@game)} alt="" class="h-14 rounded-lg" />
                Current image. Uploading a new one replaces it.
              </div>
              <.live_file_input
                upload={@uploads.image}
                class="block w-full cursor-pointer rounded-lg border border-base-300 bg-base-100 text-sm file:mr-3 file:cursor-pointer file:border-0 file:bg-primary file:px-4 file:py-2 file:text-primary-content hover:file:opacity-90"
              />
              <div :for={entry <- @uploads.image.entries} class="mt-2 text-sm">
                <div class="flex items-center gap-3">
                  <span class="truncate">{entry.client_name}</span>
                  <span class="text-xs text-base-content/60">{entry.progress}%</span>
                  <button
                    type="button"
                    phx-click="cancel-upload"
                    phx-value-ref={entry.ref}
                    class="ml-auto text-xs text-error"
                  >
                    Remove
                  </button>
                </div>
                <p :for={err <- upload_errors(@uploads.image, entry)} class="text-xs text-error">
                  {upload_error(err)}
                </p>
              </div>
              <p :for={err <- upload_errors(@uploads.image)} class="text-xs text-error">
                {upload_error(err)}
              </p>
            </div>

            <div class="flex justify-end gap-2 pt-2">
              <.link
                navigate={~p"/admin/games"}
                id="game-form-cancel"
                class="rounded-lg px-4 py-2 text-sm transition hover:bg-base-200"
              >
                Cancel
              </.link>
              <button
                type="submit"
                id="game-form-submit"
                phx-disable-with="Saving..."
                class="rounded-lg bg-primary px-4 py-2 text-sm font-medium text-primary-content transition hover:opacity-90"
              >
                Save
              </button>
            </div>
          </.form>
        </.panel>
      <% else %>
        <div class="flex items-center justify-between">
          <h1 class="text-2xl font-bold tracking-tight">Games</h1>
          <.link
            navigate={~p"/admin/games/new"}
            id="new-game"
            class="inline-flex items-center gap-1.5 rounded-lg bg-primary px-4 py-2 text-sm font-medium text-primary-content transition hover:opacity-90"
          >
            <.icon name="hero-plus" class="size-4" /> Add game
          </.link>
        </div>

        <ul id="admin-games" phx-update="stream" class="space-y-3">
          <li
            id="admin-games-empty"
            class="hidden rounded-2xl border border-dashed border-base-300 p-10 text-center text-base-content/60 only:block"
          >
            No games yet. Add the first one to start tracking a decomp.
          </li>
          <li
            :for={{id, game} <- @streams.games}
            id={id}
            class="flex flex-wrap items-center gap-4 rounded-2xl border border-base-300 bg-base-200/50 p-4"
          >
            <div class="h-14 w-24 shrink-0 overflow-hidden rounded-lg bg-gradient-to-br from-primary/30 to-accent/30">
              <img :if={image_url(game)} src={image_url(game)} alt="" class="size-full object-cover" />
            </div>
            <div class="min-w-0 flex-1">
              <.link navigate={~p"/games/#{game.slug}"} class="font-semibold hover:text-primary">
                {game.name}
              </.link>
              <div class="truncate text-xs text-base-content/60">{game.repo_url} · {game.branch}</div>
              <div class="mt-0.5 text-xs">
                <span :if={game.last_sync_error} class="text-error">
                  Sync failed: {game.last_sync_error}
                </span>
                <span :if={!game.last_sync_error} class="text-base-content/60">
                  {if game.last_synced_at,
                    do: "Synced #{time_ago(game.last_synced_at, DateTime.utc_now())}",
                    else: "Not synced yet"}
                </span>
              </div>
            </div>
            <div class="flex items-center gap-1 text-sm">
              <button
                id={"sync-#{game.id}"}
                phx-click="sync"
                phx-value-id={game.id}
                class="rounded-lg px-3 py-1.5 transition hover:bg-base-300"
              >
                Sync now
              </button>
              <.link
                id={"edit-#{game.id}"}
                navigate={~p"/admin/games/#{game.id}/edit"}
                class="rounded-lg px-3 py-1.5 transition hover:bg-base-300"
              >
                Edit
              </.link>
              <button
                id={"delete-#{game.id}"}
                phx-click="delete"
                phx-value-id={game.id}
                data-confirm={"Delete #{game.name} and all of its tracked data?"}
                class="rounded-lg px-3 py-1.5 text-error transition hover:bg-error/10"
              >
                Delete
              </button>
            </div>
          </li>
        </ul>
      <% end %>
    </Layouts.app>
    """
  end
end
