defmodule DcompWeb.LocaleController do
  use DcompWeb, :controller

  alias DcompWeb.Locale

  @doc "Remembers the chosen language in the session and goes back to the page it was chosen on."
  def update(conn, %{"locale" => locale}) do
    if Locale.supported?(locale) do
      conn |> put_session(:locale, locale) |> redirect(to: DcompWeb.BackPath.from(conn))
    else
      conn |> put_flash(:error, gettext("Unknown language.")) |> redirect(to: ~p"/")
    end
  end
end
