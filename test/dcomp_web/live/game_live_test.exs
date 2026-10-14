defmodule DcompWeb.GameLiveTest do
  use DcompWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Dcomp.DecompFixtures

  alias Dcomp.Decomp.Sync

  describe "index" do
    test "shows an empty state with no games", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      assert has_element?(view, "#hero")
      assert has_element?(view, "#games-empty")
    end

    test "shows a card per game, linking to it", %{conn: conn} do
      game = synced_game_fixture()
      {:ok, view, _html} = live(conn, ~p"/")
      assert has_element?(view, "#games-#{game.id}[href='/games/#{game.slug}']")
      assert has_element?(view, "#games-#{game.id}", "30.0%")
    end

    test "is visible to logged-out visitors with a log in link and no register link", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/")
      assert has_element?(view, "#nav-log-in")
      refute has_element?(view, "#nav-register")
      refute has_element?(view, "#nav-admin")
    end
  end

  describe "show" do
    setup %{conn: conn} do
      game = synced_game_fixture()
      {:ok, view, _html} = live(conn, ~p"/games/#{game.slug}")
      %{game: game, view: view}
    end

    test "renders the puzzle, completion and metrics", %{view: view, game: game} do
      assert has_element?(view, "#game-title", game.name)
      assert has_element?(view, "#puzzle[phx-hook]")
      assert has_element?(view, "#puzzle-list #puzzle-list-body")
      assert has_element?(view, "#completion", "30.0%")
      assert has_element?(view, "#stat-solved", "2")
      assert has_element?(view, "#stat-claimed", "1")
      assert has_element?(view, "#stat-unclaimed", "1")
      assert has_element?(view, "#stat-remaining", "2")
      assert has_element?(view, "#stat-expired", "1")
      assert has_element?(view, "#stat-released", "1")
      assert has_element?(view, "#burn-up")
      assert has_element?(view, "#burn-up-table")
    end

    test "ranks solvers, including the unknown one", %{view: view} do
      assert has_element?(view, "#leaderboard-ana")
      assert has_element?(view, "#leaderboard-anonymous")
    end

    test "lists open claims, what's left, strikes and activity", %{view: view} do
      assert has_element?(view, "#claims-08000400")
      assert has_element?(view, "#remaining-08000400")
      assert has_element?(view, "#remaining-08000300")
      assert has_element?(view, "#strikes-cy", "1 / 3")
      assert has_element?(view, "#activity li", "08000200")
    end

    test "hooks get their data through a ready event", %{view: view} do
      render_hook(view, "puzzle-ready", %{})
      assert_reply view, %{pieces: pieces, people: people, mode: "size", image: nil}
      assert length(pieces) == 4
      assert ["ana"] = Enum.map(people, & &1.login)
      # [addr, size, status (2 = solved), person index]
      assert ["08000100", 100, 2, 0] in pieces
      assert ["08000200", 200, 2, nil] in pieces

      render_hook(view, "burnup-ready", %{})
      assert_reply view, %{points: [[_, 1, 100], [_, 2, 300]]}
    end

    test "shows how to contribute to this game's repo", %{view: view, game: game} do
      assert has_element?(view, "#contribute-open")
      assert has_element?(view, "#contribute-modal")
      assert has_element?(view, "#contribute-clone", "git clone #{game.repo_url}")
      assert has_element?(view, "#contribute-modal a[href='#{game.repo_url}']")
      refute has_element?(view, "#contribute-rom-sha1")
    end

    test "pushes fresh data to the hooks after a sync", %{view: view, game: game} do
      Phoenix.PubSub.broadcast(Dcomp.PubSub, Sync.topic(game.slug), {:synced, game.slug})
      assert_push_event(view, "puzzle:data", %{mode: "size"})
      assert_push_event(view, "burnup:data", %{points: [_ | _]})
    end
  end

  test "shows the expected ROM SHA1 when the game has one", %{conn: conn} do
    sha = String.duplicate("ab", 20)
    game = synced_game_fixture() |> Ecto.Changeset.change(rom_sha1: sha) |> Dcomp.Repo.update!()
    {:ok, view, _html} = live(conn, ~p"/games/#{game.slug}")
    assert has_element?(view, "#contribute-rom-sha1", sha)
  end

  test "an unknown game is a 404", %{conn: conn} do
    assert_error_sent 404, fn -> get(conn, ~p"/games/nope") end
  end

  test "a game that was never synced renders with zeroes", %{conn: conn} do
    game = game_fixture()
    {:ok, view, _html} = live(conn, ~p"/games/#{game.slug}")
    assert has_element?(view, "#completion", "0.0%")
    assert has_element?(view, "#leaderboard-empty")
    assert has_element?(view, "#claims-empty")
  end

  test "shows a notice when the last sync failed", %{conn: conn} do
    game = game_fixture()
    Dcomp.Repo.update!(Dcomp.Decomp.Game.sync_changeset(game, %{last_sync_error: "boom"}))
    {:ok, view, _html} = live(conn, ~p"/games/#{game.slug}")
    assert has_element?(view, "#sync-error")
  end
end
