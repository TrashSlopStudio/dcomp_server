defmodule DcompWeb.LiteController do
  use DcompWeb, :controller

  @doc "Turns lite mode on or off for this browser and goes back to the page it was toggled on."
  def update(conn, %{"mode" => mode}) when mode in ~w(on off) do
    conn |> put_session(:lite, mode == "on") |> redirect(to: DcompWeb.BackPath.from(conn))
  end

  def update(conn, _params), do: redirect(conn, to: ~p"/")
end
