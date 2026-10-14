defmodule DcompWeb.BackPath do
  @moduledoc "Where to send a visitor back to after a preference link."
  use DcompWeb, :verified_routes
  import Plug.Conn

  @doc """
  The path (and query) of a same-host referer, or `/`. Only a plain absolute path is used, so this
  can't redirect off the site (`//host` is rejected too).
  """
  def from(conn) do
    with [referer | _] <- get_req_header(conn, "referer"),
         %URI{host: host, path: "/" <> rest = path} = uri when host == conn.host <-
           URI.parse(referer),
         false <- String.starts_with?(rest, "/") do
      if uri.query, do: path <> "?" <> uri.query, else: path
    else
      _ -> ~p"/"
    end
  end
end
