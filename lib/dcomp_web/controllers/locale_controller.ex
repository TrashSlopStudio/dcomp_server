defmodule DcompWeb.LocaleController do
  use DcompWeb, :controller

  alias DcompWeb.Locale

  @doc "Remembers the chosen language in the session and goes back to the page it was chosen on."
  def update(conn, %{"locale" => locale}) do
    if Locale.supported?(locale) do
      conn |> put_session(:locale, locale) |> redirect(to: back_path(conn))
    else
      conn |> put_flash(:error, gettext("Unknown language.")) |> redirect(to: ~p"/")
    end
  end

  # Only the path of a same-host referer is used, so this can't redirect off the site.
  defp back_path(conn) do
    with [referer | _] <- get_req_header(conn, "referer"),
         %URI{host: host, path: "/" <> _ = path} = uri when host == conn.host <-
           URI.parse(referer) do
      if uri.query, do: path <> "?" <> uri.query, else: path
    else
      _ -> ~p"/"
    end
  end
end
