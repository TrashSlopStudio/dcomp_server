defmodule Dcomp.Decomp.Strike do
  @moduledoc "Expired-claim count of a contributor in a game (pool/strikes/<login>)."
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "strikes" do
    field :count, :integer, default: 0

    belongs_to :game, Dcomp.Decomp.Game
    belongs_to :contributor, Dcomp.Decomp.Contributor

    timestamps(type: :utc_datetime)
  end
end
