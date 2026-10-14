defmodule Dcomp.Decomp.Setting do
  @moduledoc "Single-row, admin-managed site configuration."
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "settings" do
    field :api_key_hash, :string, redact: true
    field :poll_interval_s, :integer, default: 300
    field :layout_mode, Ecto.Enum, values: [:size, :grid], default: :size

    timestamps(type: :utc_datetime)
  end

  @min_poll_interval_s 30
  # Process.send_after overflows past ~49 days in ms; a day is plenty for a poll.
  @max_poll_interval_s 86_400

  def min_poll_interval_s, do: @min_poll_interval_s
  def max_poll_interval_s, do: @max_poll_interval_s

  def changeset(setting, attrs) do
    setting
    |> cast(attrs, [:poll_interval_s, :layout_mode])
    |> validate_required([:poll_interval_s, :layout_mode])
    |> validate_number(:poll_interval_s,
      greater_than_or_equal_to: @min_poll_interval_s,
      less_than_or_equal_to: @max_poll_interval_s
    )
  end

  def api_key_changeset(setting, hash), do: change(setting, api_key_hash: hash)
end
