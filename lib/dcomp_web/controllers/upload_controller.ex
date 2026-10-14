defmodule DcompWeb.UploadController do
  use DcompWeb, :controller

  alias Dcomp.Decomp.Uploads

  # Names are random and replaced (not edited) on change, so responses can be cached for good.
  def show(conn, %{"name" => name}) do
    with path when is_binary(path) <- Uploads.path(name),
         true <- File.regular?(path) do
      conn
      |> put_resp_content_type(Uploads.content_type(name), nil)
      |> put_resp_header("cache-control", "public, max-age=31536000, immutable")
      |> put_resp_header("x-content-type-options", "nosniff")
      |> send_file(200, path)
    else
      _ -> send_resp(conn, 404, "Not found")
    end
  end
end
