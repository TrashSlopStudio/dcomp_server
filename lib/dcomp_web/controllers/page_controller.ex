defmodule DcompWeb.PageController do
  use DcompWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
