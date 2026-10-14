defmodule DcompWeb.AdminLive.Settings do
  @moduledoc "Admin: poll interval, puzzle layout and the global API key."
  use DcompWeb, :live_view

  import DcompWeb.GameComponents

  alias Dcomp.Decomp

  @impl true
  def mount(_params, _session, socket) do
    settings = Decomp.get_settings()

    {:ok,
     socket
     |> assign(
       page_title: "Settings · Admin",
       settings: settings,
       form: to_form(Decomp.change_settings(settings)),
       new_key: nil,
       base_url: DcompWeb.Endpoint.url()
     )}
  end

  @impl true
  def handle_event("validate", %{"setting" => params}, socket) do
    form = socket.assigns.settings |> Decomp.change_settings(params) |> to_form(action: :validate)
    {:noreply, assign(socket, form: form)}
  end

  def handle_event("save", %{"setting" => params}, socket) do
    case Decomp.update_settings(socket.assigns.settings, params) do
      {:ok, settings} ->
        if settings.poll_interval_s != socket.assigns.settings.poll_interval_s,
          do: Dcomp.Decomp.Syncer.reschedule()

        {:noreply,
         socket
         |> assign(settings: settings, form: to_form(Decomp.change_settings(settings)))
         |> put_flash(:info, "Settings saved.")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  def handle_event("rotate-key", _params, socket) do
    {:ok, key} = Decomp.rotate_api_key()
    {:noreply, assign(socket, new_key: key, settings: Decomp.get_settings())}
  end

  def handle_event("dismiss-key", _params, socket), do: {:noreply, assign(socket, new_key: nil)}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} wide>
      <.admin_tabs active={:settings} />

      <div class="grid gap-6 lg:grid-cols-2">
        <.panel id="settings-panel" title="Sync and puzzle">
          <.form
            for={@form}
            id="settings-form"
            phx-change="validate"
            phx-submit="save"
            class="space-y-2"
          >
            <.input
              field={@form[:poll_interval_s]}
              type="number"
              label="Poll interval (seconds)"
              min={Dcomp.Decomp.Setting.min_poll_interval_s()}
            />
            <p class="text-xs text-base-content/60">
              How often every game's repo is fetched, even if no webhook arrives.
            </p>
            <.input
              field={@form[:layout_mode]}
              type="select"
              label="Puzzle layout"
              options={[{"Pieces sized by function size", "size"}, {"Equal-sized pieces", "grid"}]}
            />
            <div class="flex justify-end pt-2">
              <button
                type="submit"
                id="settings-submit"
                phx-disable-with="Saving..."
                class="rounded-lg bg-primary px-4 py-2 text-sm font-medium text-primary-content transition hover:opacity-90"
              >
                Save
              </button>
            </div>
          </.form>
        </.panel>

        <.panel id="api-key-panel" title="API key">
          <p class="text-sm text-base-content/70">
            One key for every game. GitHub Actions use it to ask for an early sync; the server still reads the repo itself.
            <span :if={@settings.api_key_hash} id="api-key-status" class="font-medium">
              A key is set.
            </span>
            <span :if={!@settings.api_key_hash} id="api-key-status" class="font-medium text-warning">
              No key yet, so webhooks are rejected.
            </span>
          </p>

          <div
            :if={@new_key}
            id="new-api-key"
            class="mt-4 space-y-2 rounded-xl border border-success/50 bg-success/10 p-4"
          >
            <p class="text-sm font-medium">Copy it now: it can't be shown again.</p>
            <code
              id="new-api-key-value"
              class="block break-all rounded-lg bg-base-300 p-2 text-xs select-all"
            >
              {@new_key}
            </code>
            <button
              type="button"
              id="dismiss-key"
              phx-click="dismiss-key"
              class="text-xs text-base-content/60 hover:text-base-content"
            >
              I've saved it
            </button>
          </div>

          <button
            type="button"
            id="rotate-key"
            phx-click="rotate-key"
            data-confirm={
              if @settings.api_key_hash,
                do: "Replace the current key? Workflows using it will stop working.",
                else: nil
            }
            class="mt-4 rounded-lg border border-base-300 px-4 py-2 text-sm font-medium transition hover:bg-base-300"
          >
            {if @settings.api_key_hash, do: "Rotate key", else: "Generate key"}
          </button>

          <details class="mt-5 text-sm">
            <summary class="cursor-pointer select-none text-base-content/70 hover:text-primary">
              GitHub Action step
            </summary>
            <p class="mt-2 text-xs text-base-content/60">
              Store the key as the repository secret <code>DCOMP_API_KEY</code>, then add:
            </p>
            <pre
              id="action-snippet"
              phx-no-curly-interpolation
              class="mt-2 overflow-x-auto rounded-lg bg-base-300 p-3 text-xs"
            ><%= "- name: Notify dcomp\n  if: always()\n  run: >\n    curl -fsS -X POST\n    -H \"Authorization: Bearer ${{ secrets.DCOMP_API_KEY }}\"\n    #{@base_url}/api/games/GAME-SLUG/sync" %></pre>
          </details>
        </.panel>
      </div>
    </Layouts.app>
    """
  end
end
