defmodule DcompWeb.GameLiveLayoutModeTest do
  # async: false - changes the global settings row, which every other test reads
  use DcompWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Dcomp.DecompFixtures

  test "the puzzle uses the layout mode from settings", %{conn: conn} do
    game = synced_game_fixture()
    {:ok, _} = Dcomp.Decomp.update_settings(Dcomp.Decomp.get_settings(), %{layout_mode: :grid})
    {:ok, view, _} = live(conn, ~p"/games/#{game.id}")
    render_hook(view, "puzzle-ready", %{})
    assert_reply view, %{mode: "grid"}
  end

  test "a viewer can switch the piece layout", %{conn: conn} do
    game = synced_game_fixture()
    {:ok, view, _} = live(conn, ~p"/games/#{game.id}")
    assert has_element?(view, "#layout-size[aria-pressed=true]")

    view |> element("#layout-grid") |> render_click()
    assert has_element?(view, "#layout-grid[aria-pressed=true]")
    assert_push_event(view, "puzzle:data", %{mode: "grid"})

    view |> element("#layout-size") |> render_click()
    assert_push_event(view, "puzzle:data", %{mode: "size"})
  end
end
