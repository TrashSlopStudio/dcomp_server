defmodule DcompWeb.LocaleTest do
  use DcompWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Dcomp.DecompFixtures

  alias DcompWeb.GameComponents

  describe "choosing the language" do
    test "defaults to English", %{conn: conn} do
      conn = get(conn, ~p"/users/log-in")
      assert get_session(conn, :locale) == "en"
      assert html_response(conn, 200) =~ "Log in with email"
    end

    test "follows Accept-Language, any Spanish becoming Argentine Spanish", %{conn: conn} do
      conn =
        conn |> put_req_header("accept-language", "es-MX,en;q=0.5") |> get(~p"/users/log-in")

      assert get_session(conn, :locale) == "es_AR"
      assert html_response(conn, 200) =~ "Iniciar sesión con email"
    end

    test "an explicit choice beats Accept-Language and is remembered", %{conn: conn} do
      conn =
        conn
        |> put_req_header("accept-language", "es-AR")
        |> get(~p"/locale/en")
        |> recycle()
        |> put_req_header("accept-language", "es-AR")
        |> get(~p"/users/log-in")

      assert get_session(conn, :locale) == "en"
      assert html_response(conn, 200) =~ "Log in with email"
    end

    test "goes back to the page it was chosen on, never off the site", %{conn: conn} do
      conn =
        conn
        |> put_req_header("referer", "http://www.example.com/games/x?a=1")
        |> get(~p"/locale/es_AR")

      assert redirected_to(conn) == "/games/x?a=1"
      assert get_session(conn, :locale) == "es_AR"

      conn =
        build_conn()
        |> put_req_header("referer", "https://evil.example/steal")
        |> get(~p"/locale/es_AR")

      assert redirected_to(conn) == "/"
    end

    test "ignores a language we don't have", %{conn: conn} do
      conn = get(conn, ~p"/locale/xx")
      assert redirected_to(conn) == "/"
      refute get_session(conn, :locale) == "xx"
    end
  end

  describe "the LiveViews" do
    test "render in Spanish when the session says so", %{conn: conn} do
      conn = init_test_session(conn, %{"locale" => "es_AR"})
      {:ok, view, _} = live(conn, ~p"/")
      assert has_element?(view, "#hero", "Pieza por pieza, byte por byte")
      assert has_element?(view, "#locale-es_AR[aria-current=true]")
    end

    test "the game page too, including the strings its hooks draw", %{conn: conn} do
      game = synced_game_fixture()
      conn = init_test_session(conn, %{"locale" => "es_AR"})
      {:ok, view, _} = live(conn, ~p"/games/#{game.slug}")
      assert has_element?(view, "#contribute-open", "Contribuir")
      assert has_element?(view, "#puzzle[data-i18n*='Sin reclamar']")
    end
  end

  describe "formatting" do
    test "numbers use the local separators" do
      Gettext.put_locale(DcompWeb.Gettext, "en")
      assert GameComponents.number(9487) == "9,487"
      assert GameComponents.percent(0.8) == "0.8%"

      Gettext.put_locale(DcompWeb.Gettext, "es_AR")
      assert GameComponents.number(9487) == "9.487"
      assert GameComponents.percent(0.8) == "0,8%"
      assert GameComponents.bytes(2048) == "2,0 KiB"
    end

    test "relative times are translated" do
      now = ~U[2026-01-02 00:00:00Z]
      Gettext.put_locale(DcompWeb.Gettext, "es_AR")
      assert GameComponents.time_ago(~U[2026-01-01 23:55:00Z], now) == "hace 5 min"
      assert GameComponents.time_ago(nil, now) == "nunca"
      assert GameComponents.eta(200) =~ "meses"
    end
  end
end
