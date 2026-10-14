defmodule Dcomp.Decomp.Contributor do
  @moduledoc "A GitHub user seen in a game repo. Identified only by login; no email is stored."
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "contributors" do
    field :login, :string
    field :avatar_url, :string

    timestamps(type: :utc_datetime)
  end

  def avatar_url_for(login), do: "https://github.com/#{login}.png"
end
