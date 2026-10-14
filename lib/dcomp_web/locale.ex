defmodule DcompWeb.Locale do
  @moduledoc """
  Picks the interface language: an explicit choice (kept in the session) wins, then the browser's
  `Accept-Language`, then English. Spanish is Argentine (`es_AR`, voseo).

  Used as a plug in the browser pipeline and as a LiveView `on_mount` hook, since a LiveView runs
  in its own process and needs the locale set again there.
  """
  import Plug.Conn

  @default "en"
  @locales ~w(en es_AR)

  def locales, do: @locales

  def supported?(locale), do: locale in @locales

  @doc "Short label for the language switcher."
  def label("es_AR"), do: "ES"
  def label(_), do: "EN"

  def init(opts), do: opts

  def call(conn, _opts) do
    locale =
      with nil <- get_session(conn, :locale),
           nil <- from_accept_language(get_req_header(conn, "accept-language")) do
        @default
      end

    Gettext.put_locale(DcompWeb.Gettext, locale)
    put_session(conn, :locale, locale)
  end

  def on_mount(:default, _params, session, socket) do
    locale = if supported?(session["locale"]), do: session["locale"], else: @default
    Gettext.put_locale(DcompWeb.Gettext, locale)
    {:cont, socket}
  end

  # "es-AR,es;q=0.9,en;q=0.8" -> the first language we have, in the browser's order.
  defp from_accept_language([header | _]) do
    header
    |> String.split(",")
    |> Enum.map(&(&1 |> String.split(";") |> hd() |> String.trim() |> String.downcase()))
    |> Enum.find_value(fn
      "es" <> _ -> "es_AR"
      "en" <> _ -> "en"
      _ -> nil
    end)
  end

  defp from_accept_language(_), do: nil
end
