defmodule DcompWeb.ErrorHTMLTest do
  use DcompWeb.ConnCase, async: true

  import Phoenix.Template, only: [render_to_string: 4]

  test "renders 404.html" do
    html = render_to_string(DcompWeb.ErrorHTML, "404", "html", [])
    assert html =~ ~s(id="error-code")
    assert html =~ "404"
    assert html =~ ~s(href="/")
  end

  test "renders 500.html" do
    assert render_to_string(DcompWeb.ErrorHTML, "500", "html", []) =~ "500"
  end

  test "renders other statuses with their status text" do
    assert render_to_string(DcompWeb.ErrorHTML, "400", "html", []) =~ "Bad Request"
  end

  test "an unknown route is a 404 page inside the layout", %{conn: conn} do
    {404, _headers, html} = assert_error_sent(404, fn -> get(conn, "/games/nope") end)
    assert html =~ ~s(id="error-page")
    assert html =~ "<html"
  end
end
