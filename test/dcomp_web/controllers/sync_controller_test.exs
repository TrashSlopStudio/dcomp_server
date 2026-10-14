defmodule DcompWeb.SyncControllerTest do
  # async: false - registers this process under the Syncer's global name
  use DcompWeb.ConnCase, async: false

  alias Dcomp.Decomp

  setup do
    {:ok, game} =
      Decomp.create_game(%{name: "Drill Dozer", repo_url: "https://example.com/x/y"})

    {:ok, key} = Decomp.rotate_api_key()
    Process.register(self(), Dcomp.Decomp.Syncer)
    %{game: game, key: key}
  end

  defp post_sync(conn, slug, key) do
    conn = if key, do: put_req_header(conn, "authorization", "Bearer " <> key), else: conn
    post(conn, ~p"/api/games/#{slug}/sync")
  end

  test "queues a sync for a known game", %{conn: conn, game: game, key: key} do
    conn = post_sync(conn, game.slug, key)
    assert json_response(conn, 202) == %{"status" => "queued"}
    slug = game.slug
    assert_received {:"$gen_cast", {:sync, ^slug}}
  end

  test "404 for an unknown game", %{conn: conn, key: key} do
    assert json_response(post_sync(conn, "nope", key), 404)
    refute_received {:"$gen_cast", _}
  end

  test "401 without a key, with a wrong key, or after rotation", %{
    conn: conn,
    game: game,
    key: key
  } do
    assert json_response(post_sync(conn, game.slug, nil), 401)
    assert json_response(post_sync(conn, game.slug, "wrong"), 401)
    {:ok, _new} = Decomp.rotate_api_key()
    assert json_response(post_sync(conn, game.slug, key), 401)
    refute_received {:"$gen_cast", _}
  end
end
