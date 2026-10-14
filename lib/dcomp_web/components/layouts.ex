defmodule DcompWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use DcompWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  attr :wide, :boolean, default: false, doc: "use the full page width (dashboards)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="sticky top-0 z-30 border-b border-base-300 bg-base-100/80 backdrop-blur">
      <nav
        id="site-nav"
        class="mx-auto flex h-14 max-w-7xl items-center gap-4 px-4 sm:px-6 lg:px-8"
      >
        <.link
          navigate={~p"/"}
          id="nav-home"
          class="flex items-center gap-2 text-base font-bold tracking-tight"
        >
          <.icon name="hero-puzzle-piece-solid" class="size-6 text-primary" /> dcomp
        </.link>

        <div class="ml-auto flex items-center gap-1 text-sm sm:gap-2">
          <%= if @current_scope && @current_scope.user do %>
            <.link
              :if={Dcomp.Accounts.User.admin?(@current_scope.user)}
              navigate={~p"/admin/games"}
              id="nav-admin"
              class="rounded-lg px-3 py-1.5 transition hover:bg-base-200"
            >
              {gettext("Admin")}
            </.link>
            <.link
              href={~p"/users/settings"}
              id="nav-settings"
              class="hidden rounded-lg px-3 py-1.5 transition hover:bg-base-200 sm:block"
            >
              {@current_scope.user.email}
            </.link>
            <.link
              href={~p"/users/log-out"}
              method="delete"
              id="nav-log-out"
              class="rounded-lg px-3 py-1.5 transition hover:bg-base-200"
            >
              {gettext("Log out")}
            </.link>
          <% else %>
            <.link
              href={~p"/users/log-in"}
              id="nav-log-in"
              class="rounded-lg px-3 py-1.5 transition hover:bg-base-200"
            >
              {gettext("Log in")}
            </.link>
          <% end %>
          <.language_switcher />
          <.theme_toggle />
        </div>
      </nav>
    </header>

    <main class="px-4 py-10 sm:px-6 lg:px-8">
      <div class={["mx-auto space-y-6", if(@wide, do: "max-w-7xl", else: "max-w-2xl")]}>
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc "Language links in the nav; the current one is marked."
  def language_switcher(assigns) do
    assigns = assign(assigns, :current, Gettext.get_locale(DcompWeb.Gettext))

    ~H"""
    <div id="language-switcher" class="flex items-center rounded-lg text-xs font-medium">
      <.link
        :for={locale <- DcompWeb.Locale.locales()}
        id={"locale-#{locale}"}
        href={~p"/locale/#{locale}"}
        aria-current={if(locale == @current, do: "true")}
        title={if(locale == "es_AR", do: "Español (Argentina)", else: "English")}
        class={[
          "rounded-md px-2 py-1 transition",
          if(locale == @current,
            do: "bg-base-200 text-base-content",
            else: "text-base-content/60 hover:text-base-content"
          )
        ]}
      >
        {DcompWeb.Locale.label(locale)}
      </.link>
    </div>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 [[data-theme-source=system]_&]:!left-0 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
