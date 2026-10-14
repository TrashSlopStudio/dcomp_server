defmodule Dcomp.Decomp.Game do
  @moduledoc "A decompilation project, backed by a git repository."
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "games" do
    field :name, :string
    field :slug, :string
    field :repo_url, :string
    field :branch, :string, default: "main"
    field :image_path, :string
    field :rom_sha1, :string
    field :last_synced_sha, :string
    field :last_synced_at, :utc_datetime
    field :last_sync_error, :string
    # Read from the repo's pool.toml on sync, never cast from user input.
    field :claim_hours, :integer
    field :max_claims, :integer
    field :max_strikes, :integer

    has_many :functions, Dcomp.Decomp.Function
    has_many :events, Dcomp.Decomp.Event

    timestamps(type: :utc_datetime)
  end

  def changeset(game, attrs) do
    game
    |> cast(attrs, [:name, :slug, :repo_url, :branch, :rom_sha1])
    |> validate_required([:name, :repo_url, :branch])
    |> update_change(:rom_sha1, &normalize_sha/1)
    |> validate_format(:rom_sha1, ~r/^[0-9a-f]{40}$/, message: "must be 40 hex characters")
    |> put_default_slug()
    |> validate_format(:slug, ~r/^[a-z0-9]+(-[a-z0-9]+)*$/,
      message: "use lowercase letters, numbers and dashes"
    )
    # git clones this URL, so only plain https is accepted (no file://, ssh, ext::).
    |> validate_format(:repo_url, ~r{^https://[^\s]+$}, message: "must be an https:// URL")
    |> validate_format(:branch, ~r{^[A-Za-z0-9][A-Za-z0-9._/-]*$}, message: "invalid branch name")
    |> unique_constraint(:slug)
  end

  def image_changeset(game, image_path), do: change(game, image_path: image_path)

  def sync_changeset(game, attrs) do
    cast(game, attrs, [
      :last_synced_sha,
      :last_synced_at,
      :last_sync_error,
      :claim_hours,
      :max_claims,
      :max_strikes
    ])
  end

  # `cast` turns an emptied field into a nil change, which must stay nil.
  defp normalize_sha(nil), do: nil
  defp normalize_sha(sha), do: sha |> String.trim() |> String.downcase()

  defp put_default_slug(changeset) do
    with nil <- get_field(changeset, :slug),
         name when is_binary(name) <- get_field(changeset, :name) do
      slug = name |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-") |> String.trim("-")
      put_change(changeset, :slug, slug)
    else
      _ -> changeset
    end
  end
end
