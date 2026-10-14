defmodule DcompWeb.Lite do
  @moduledoc """
  "Lite" mode: a plain, vintage-looking site with no canvas/JS charts or animation, to save
  browser resources. The choice lives in the session (like the locale) so the server can render it.

  Used as a plug in the browser pipeline and as a LiveView `on_mount` hook.
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts), do: assign(conn, :lite, get_session(conn, :lite) == true)

  def on_mount(:default, _params, session, socket) do
    {:cont, Phoenix.Component.assign(socket, :lite, session["lite"] == true)}
  end
end
