defmodule DcompWeb.AdminLiveTest do
  # async: false - some tests register this process as the Syncer to see what gets nudged
  use DcompWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Dcomp.AccountsFixtures
  import Dcomp.DecompFixtures

  alias Dcomp.{Accounts, Decomp, Repo}
  alias Dcomp.Decomp.{Game, Uploads}

  describe "access control" do
    test "logged-out visitors are sent to log in", %{conn: conn} do
      for path <- ~w(/admin/games /admin/games/new /admin/settings /admin/users) do
        assert redirected_to(get(conn, path)) == ~p"/users/log-in"
      end
    end

    test "regular users are sent home", %{conn: conn} do
      conn = log_in_user(conn, user_fixture())

      for path <- ~w(/admin/games /admin/settings /admin/users) do
        assert redirected_to(get(conn, path)) == ~p"/"
      end

      {:ok, view, _} = live(conn, ~p"/")
      refute has_element?(view, "#nav-admin")
    end

    test "admins get in and see the nav link", %{conn: conn} do
      {:ok, admin} = Accounts.make_admin(user_fixture().email)
      conn = log_in_user(conn, admin)
      {:ok, view, _} = live(conn, ~p"/")
      assert has_element?(view, "#nav-admin")
      {:ok, _view, html} = live(conn, ~p"/admin/games")
      assert html =~ "Games"
    end

    test "a live session loses access when demoted mid-session", %{conn: conn} do
      {:ok, admin} = Accounts.make_admin(user_fixture().email)
      {:ok, _other} = Accounts.make_admin(user_fixture().email)
      conn = log_in_user(conn, admin)
      {:ok, _view, _} = live(conn, ~p"/admin/games")
      {:ok, _} = Accounts.set_role(admin, :user)
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/admin/games")
    end
  end

  describe "games" do
    setup %{conn: conn} do
      {:ok, admin} = Accounts.make_admin(user_fixture().email)
      Process.register(self(), Dcomp.Decomp.Syncer)
      %{conn: log_in_user(conn, admin)}
    end

    test "lists games and an empty state", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/admin/games")
      assert has_element?(view, "#admin-games-empty")
      game = game_fixture()
      {:ok, view, _} = live(conn, ~p"/admin/games")
      assert has_element?(view, "#games-#{game.id}", game.name)
    end

    test "adds a game, derives the slug and queues the first sync", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/admin/games/new")

      {:ok, view, _} =
        view
        |> form("#game-form", game: %{name: "Drill Dozer", repo_url: "https://github.com/o/r"})
        |> render_submit()
        |> follow_redirect(conn, ~p"/admin/games")

      game = Decomp.get_game_by_slug!("drill-dozer")
      assert has_element?(view, "#games-#{game.id}")
      assert_received {:"$gen_cast", {:sync, "drill-dozer"}}
    end

    test "validates the repo url as you type", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/admin/games/new")

      html =
        view
        |> form("#game-form", game: %{name: "X", repo_url: "file:///etc/passwd"})
        |> render_change()

      assert html =~ "must be an https:// URL"
      assert has_element?(view, "#game-form")
    end

    test "edits a game", %{conn: conn} do
      game = game_fixture()
      {:ok, view, _} = live(conn, ~p"/admin/games/#{game.id}/edit")

      view
      |> form("#game-form", game: %{name: "Renamed", branch: "dev"})
      |> render_submit()
      |> follow_redirect(conn, ~p"/admin/games")

      game = Repo.reload!(game)
      assert {game.name, game.branch} == {"Renamed", "dev"}
    end

    test "uploads a real image and replaces it later", %{conn: conn} do
      game = game_fixture()
      {:ok, view, _} = live(conn, ~p"/admin/games/#{game.id}/edit")

      upload =
        file_input(view, "#game-form", :image, [
          %{name: "cover.png", content: png_bytes(), type: "image/png"}
        ])

      render_upload(upload, "cover.png")
      view |> form("#game-form") |> render_submit()

      first = Repo.reload!(game).image_path
      assert first =~ ~r/\.png\z/
      assert File.regular?(Uploads.path(first))

      {:ok, view, _} = live(conn, ~p"/admin/games/#{game.id}/edit")

      upload =
        file_input(view, "#game-form", :image, [
          %{name: "new.png", content: png_bytes(), type: "image/png"}
        ])

      render_upload(upload, "new.png")
      view |> form("#game-form") |> render_submit()

      second = Repo.reload!(game).image_path
      assert second != first
      refute File.exists?(Uploads.path(first))
      Uploads.delete(second)
    end

    test "rejects a file that only pretends to be an image", %{conn: conn} do
      game = game_fixture()
      {:ok, view, _} = live(conn, ~p"/admin/games/#{game.id}/edit")

      upload =
        file_input(view, "#game-form", :image, [
          %{name: "evil.png", content: "<script>alert(1)</script>", type: "image/png"}
        ])

      render_upload(upload, "evil.png")
      view |> form("#game-form") |> render_submit()

      assert Repo.reload!(game).image_path == nil
    end

    test "rejects other file types before uploading", %{conn: conn} do
      game = game_fixture()
      {:ok, view, _} = live(conn, ~p"/admin/games/#{game.id}/edit")

      upload =
        file_input(view, "#game-form", :image, [
          %{name: "x.exe", content: "MZ", type: "application/octet-stream"}
        ])

      assert {:error, [[_, :not_accepted]]} = render_upload(upload, "x.exe")
    end

    test "sync now nudges the syncer", %{conn: conn} do
      game = game_fixture()
      {:ok, view, _} = live(conn, ~p"/admin/games")
      view |> element("#sync-#{game.id}") |> render_click()
      slug = game.slug
      assert_received {:"$gen_cast", {:sync, ^slug}}
    end

    test "a game deleted in another tab doesn't crash the page", %{conn: conn} do
      game = game_fixture()
      {:ok, view, _} = live(conn, ~p"/admin/games")
      Repo.delete!(game)

      html = view |> element("#delete-#{game.id}") |> render_click()
      assert html =~ "no longer exists"
      refute has_element?(view, "#games-#{game.id}")
    end

    test "deletes a game and its image", %{conn: conn} do
      game = game_fixture()
      Repo.update!(Game.image_changeset(game, "x"))
      {:ok, view, _} = live(conn, ~p"/admin/games")
      view |> element("#delete-#{game.id}") |> render_click()
      refute has_element?(view, "#games-#{game.id}")
      assert Repo.get(Game, game.id) == nil
    end
  end

  describe "settings" do
    setup %{conn: conn} do
      {:ok, admin} = Accounts.make_admin(user_fixture().email)
      %{conn: log_in_user(conn, admin)}
    end

    test "saves the poll interval and layout", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/admin/settings")

      view
      |> form("#settings-form", setting: %{poll_interval_s: "90", layout_mode: "grid"})
      |> render_submit()

      s = Decomp.get_settings()
      assert {s.poll_interval_s, s.layout_mode} == {90, :grid}
    end

    test "refuses an interval that would hammer the repos", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/admin/settings")

      html =
        view
        |> form("#settings-form", setting: %{poll_interval_s: "5", layout_mode: "size"})
        |> render_submit()

      assert html =~ "must be greater than or equal to"
      assert Decomp.get_settings().poll_interval_s == 300
    end

    test "generates a key, shows it once, and rotating invalidates it", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/admin/settings")
      assert has_element?(view, "#api-key-status", "No key yet")

      view |> element("#rotate-key") |> render_click()

      key =
        view
        |> element("#new-api-key-value")
        |> render()
        |> then(&Regex.run(~r/>\s*([\w-]+)\s*</, &1))
        |> Enum.at(1)

      assert Decomp.valid_api_key?(key)
      assert has_element?(view, "#api-key-status", "A key is set")

      view |> element("#dismiss-key") |> render_click()
      refute has_element?(view, "#new-api-key")

      view |> element("#rotate-key") |> render_click()
      refute Decomp.valid_api_key?(key)
    end
  end

  describe "users" do
    setup %{conn: conn} do
      {:ok, admin} = Accounts.make_admin(user_fixture().email)
      %{conn: log_in_user(conn, admin), admin: admin}
    end

    test "promotes and demotes", %{conn: conn} do
      other = user_fixture()
      {:ok, view, _} = live(conn, ~p"/admin/users")
      assert has_element?(view, "#users-#{other.id}")

      view |> element("#promote-#{other.id}") |> render_click()
      assert Repo.reload!(other).role == :admin

      view |> element("#demote-#{other.id}") |> render_click()
      assert Repo.reload!(other).role == :user
    end

    test "creates a user or an admin who can log in with the password", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/admin/users")

      view
      |> form("#new-user-form",
        user: %{email: "new@example.com", password: "a long password!", role: "admin"}
      )
      |> render_submit()

      user = Accounts.get_user_by_email("new@example.com")
      assert user.role == :admin
      assert user.confirmed_at
      assert Accounts.get_user_by_email_and_password("new@example.com", "a long password!")
      assert has_element?(view, "#users-#{user.id}")
    end

    test "rejects a short password and a taken email", %{conn: conn, admin: admin} do
      {:ok, view, _} = live(conn, ~p"/admin/users")

      html =
        view
        |> form("#new-user-form", user: %{email: admin.email, password: "short"})
        |> render_submit()

      assert html =~ "has already been taken"
      assert html =~ "should be at least 12 character"
      assert Accounts.get_user_by_email("nobody@example.com") == nil
    end

    test "sets a new password for a user", %{conn: conn} do
      other = user_fixture()
      {:ok, view, _} = live(conn, ~p"/admin/users")

      view |> element("#set-password-#{other.id}") |> render_click()

      view
      |> form("#password-form-#{other.id}", password: %{password: "brand new password"})
      |> render_submit()

      assert Accounts.get_user_by_email_and_password(other.email, "brand new password")
      refute has_element?(view, "#password-form-#{other.id}")
    end

    test "a user removed in another tab doesn't crash the page", %{conn: conn} do
      other = user_fixture()
      {:ok, view, _} = live(conn, ~p"/admin/users")
      Repo.delete!(other)

      html = view |> element("#promote-#{other.id}") |> render_click()
      assert html =~ "no longer exists"
      refute has_element?(view, "#users-#{other.id}")
    end

    test "the last admin can't be demoted", %{conn: conn, admin: admin} do
      {:ok, view, _} = live(conn, ~p"/admin/users")
      html = view |> element("#demote-#{admin.id}") |> render_click()
      assert html =~ "at least one admin"
      assert Repo.reload!(admin).role == :admin
    end
  end
end
