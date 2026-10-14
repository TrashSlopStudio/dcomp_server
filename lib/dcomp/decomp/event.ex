defmodule Dcomp.Decomp.Event do
  @moduledoc "Something that happened in a game repo's history; feeds the time-based metrics."
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "events" do
    field :type, Ecto.Enum, values: [:claim, :solve, :release, :expire, :strike]
    field :addr, :string
    field :sha, :string
    field :occurred_at, :utc_datetime

    belongs_to :game, Dcomp.Decomp.Game
    belongs_to :contributor, Dcomp.Decomp.Contributor

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
