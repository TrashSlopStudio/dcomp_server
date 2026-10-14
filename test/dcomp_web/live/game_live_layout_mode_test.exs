defmodule DcompWeb.GameLiveLayoutModeTest do
  # async: false - changes the global settings row, which every other test reads
  use DcompWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Dcomp.DecompFixtures

  test "the puzzle uses the layout mode from settings", %{conn: conn} do
    game = synced_game_fixture()
    {:ok, _} = Dcomp.Decomp.update_settings(Dcomp.Decomp.get_settings(), %{layout_mode: :grid})
    {:ok, view, _} = live(conn, ~p"/games/#{game.slug}")
    render_hook(view, "puzzle-ready", %{})
    assert_reply view, %{mode: "grid"}
  end
end
