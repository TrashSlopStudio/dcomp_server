defmodule DcompWeb.ErrorHTML do
  @moduledoc """
  Error pages for HTML requests (see `render_errors` in config/config.exs).

  Rendered inside the root layout only, with no session, database or nav, so a 500 can't fail
  again while drawing itself.
  """
  use DcompWeb, :html

  def render("404.html", assigns) do
    page(
      Map.merge(assigns, %{
        code: 404,
        title: gettext("Page not found"),
        text: gettext("This page doesn't exist, or the game it belonged to is gone.")
      })
    )
  end

  def render("500.html", assigns) do
    page(
      Map.merge(assigns, %{
        code: 500,
        title: gettext("Something went wrong"),
        text: gettext("It's on our side. Try again in a moment.")
      })
    )
  end

  # Anything else (400, 401, ...): the status text is all there is to say.
  def render(template, assigns) do
    code = template |> Path.rootname() |> String.to_integer()

    page(
      Map.merge(assigns, %{
        code: code,
        title: Phoenix.Controller.status_message_from_template(template),
        text: nil
      })
    )
  end

  attr :code, :integer, required: true
  attr :title, :string, required: true
  attr :text, :string, default: nil

  defp page(assigns) do
    ~H"""
    <main
      id="error-page"
      class="flex min-h-screen flex-col items-center justify-center gap-4 px-6 text-center"
    >
      <.icon name="hero-puzzle-piece-solid" class="size-12 text-primary" />
      <p id="error-code" class="font-mono text-6xl font-bold tracking-tight text-primary">{@code}</p>
      <h1 id="error-title" class="text-2xl font-semibold">{@title}</h1>
      <p :if={@text} class="max-w-md text-base-content/70">{@text}</p>
      <a
        id="error-home"
        href={~p"/"}
        class="mt-2 inline-flex items-center gap-1.5 rounded-lg bg-primary px-4 py-2 font-medium text-primary-content transition hover:opacity-90"
      >
        <.icon name="hero-arrow-left" class="size-4" /> {gettext("Back to all games")}
      </a>
    </main>
    """
  end
end
