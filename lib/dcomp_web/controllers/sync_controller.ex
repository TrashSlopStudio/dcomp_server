defmodule DcompWeb.SyncController do
  use DcompWeb, :controller

  alias Dcomp.Decomp
  alias Dcomp.Decomp.Syncer

  @doc """
  Webhook target for a game's GitHub Action. Only nudges an early sync: the payload is ignored,
  the server reads the repo itself, so a bogus call can't inject state.
  """
  def create(conn, %{"slug" => slug}) do
    case Decomp.get_game_by_slug(slug) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "unknown game"})

      game ->
        Syncer.nudge(game.slug)
        conn |> put_status(:accepted) |> json(%{status: "queued"})
    end
  end
end
