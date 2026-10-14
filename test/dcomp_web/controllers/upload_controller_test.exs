defmodule DcompWeb.UploadControllerTest do
  use DcompWeb.ConnCase, async: true

  import Dcomp.DecompFixtures

  alias Dcomp.Decomp.Uploads

  setup do
    src = Path.join(System.tmp_dir!(), "ctl_src_#{System.unique_integer([:positive])}")
    File.write!(src, png_bytes())
    {:ok, name} = Uploads.save(src, "c.png")

    on_exit(fn ->
      File.rm(src)
      Uploads.delete(name)
    end)

    %{name: name}
  end

  test "serves a stored image with safe headers", %{conn: conn, name: name} do
    conn = get(conn, ~p"/uploads/#{name}")
    assert response(conn, 200)
    assert get_resp_header(conn, "content-type") == ["image/png"]
    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
    assert [cc] = get_resp_header(conn, "cache-control")
    assert cc =~ "immutable"
  end

  test "404s for anything else", %{conn: conn} do
    assert response(get(conn, ~p"/uploads/nope.png"), 404)
    assert response(get(conn, "/uploads/..%2F..%2Fmix.exs"), 404)
    assert response(get(conn, "/uploads/#{Ecto.UUID.generate()}.png"), 404)
  end
end
