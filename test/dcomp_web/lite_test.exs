defmodule DcompWeb.LiteTest do
  use DcompWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Dcomp.DecompFixtures

  test "the toggle stores the choice and returns to the page", %{conn: conn} do
    conn =
      conn |> put_req_header("referer", "http://www.example.com/games/x") |> get(~p"/lite/on")

    assert redirected_to(conn) == "/games/x"
    assert get_session(conn, :lite) == true
  end

  test "a protocol-relative referer path falls back to the home page", %{conn: conn} do
    conn =
      conn |> put_req_header("referer", "http://www.example.com//evil.com") |> get(~p"/lite/on")

    assert redirected_to(conn) == "/"
  end

  test "unknown modes are ignored", %{conn: conn} do
    conn = get(conn, ~p"/lite/bogus")
    assert redirected_to(conn) == "/"
    refute get_session(conn, :lite)
  end

  test "lite mode drops the JS puzzle and chart", %{conn: conn} do
    game = synced_game_fixture()
    {:ok, view, _} = live(conn, ~p"/games/#{game.id}")
    assert has_element?(view, "#puzzle") and has_element?(view, "#burn-up")

    {:ok, view, _} = conn |> init_test_session(%{"lite" => true}) |> live(~p"/games/#{game.id}")
    refute has_element?(view, "#puzzle")
    refute has_element?(view, "#burn-up")
    assert has_element?(view, "#burn-up-table")
    assert has_element?(view, "#puzzle-ascii")
    assert has_element?(view, "#lite-toggle")
  end

  test "lite mode drops the home backdrop", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/")
    assert has_element?(view, "#home-backdrop")
    {:ok, view, _} = conn |> init_test_session(%{"lite" => true}) |> live(~p"/")
    refute has_element?(view, "#home-backdrop")
  end
end
