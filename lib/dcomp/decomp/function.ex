defmodule Dcomp.Decomp.Function do
  @moduledoc "One function of a game's ROM, listed in the repo's functions.csv."
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "functions" do
    field :addr, :string
    field :size, :integer
    field :sha1, :string
    field :status, Ecto.Enum, values: [:unclaimed, :claimed, :solved], default: :unclaimed
    field :claimed_at, :utc_datetime
    field :solved_at, :utc_datetime
    field :solve_sha, :string

    belongs_to :game, Dcomp.Decomp.Game
    belongs_to :claimed_by, Dcomp.Decomp.Contributor
    belongs_to :solved_by, Dcomp.Decomp.Contributor

    timestamps(type: :utc_datetime)
  end
end
