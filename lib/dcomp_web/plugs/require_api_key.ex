defmodule DcompWeb.Plugs.RequireApiKey do
  @moduledoc "Requires `authorization: Bearer <key>` to match the admin-managed global API key."
  import Plug.Conn

  alias Dcomp.Decomp

  def init(opts), do: opts

  def call(conn, _opts) do
    with ["Bearer " <> key] <- get_req_header(conn, "authorization"),
         true <- Decomp.valid_api_key?(key) do
      conn
    else
      _ ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(401, ~s({"error":"invalid or missing API key"}))
        |> halt()
    end
  end
end
