defmodule Dcomp.Decomp.Uploads do
  @moduledoc """
  Game images uploaded by admins, stored in the `:uploads_path` directory under random names.

  The type is checked by the file's own bytes, not the client's file name or MIME type, and the
  stored name never contains anything the client chose except the (whitelisted) extension.
  """

  @exts ~w(.png .jpg .jpeg .webp)
  @name ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(png|jpe?g|webp)\z/

  def exts, do: @exts

  def dir, do: Application.fetch_env!(:dcomp, :uploads_path)

  @doc "Copies the file into the uploads dir. Returns `{:ok, stored_name}` or `{:error, :bad_type}`."
  def save(src, client_name) do
    ext = client_name |> Path.extname() |> String.downcase()

    if ext in @exts and signature?(src, ext) do
      name = Ecto.UUID.generate() <> ext
      File.mkdir_p!(dir())
      File.cp!(src, Path.join(dir(), name))
      {:ok, name}
    else
      {:error, :bad_type}
    end
  end

  @doc "Absolute path of a stored file, or `nil` if `name` isn't one we could have generated."
  def path(name) when is_binary(name), do: if(name =~ @name, do: Path.join(dir(), name))
  def path(_), do: nil

  def delete(name) do
    if path = path(name), do: File.rm(path)
    :ok
  end

  def content_type(name) do
    case Path.extname(name) do
      ".png" -> "image/png"
      ".webp" -> "image/webp"
      _ -> "image/jpeg"
    end
  end

  defp signature?(path, ext) do
    case File.open(path, [:read, :binary], &IO.binread(&1, 12)) do
      {:ok, head} when is_binary(head) -> match_signature?(ext, head)
      _ -> false
    end
  end

  defp match_signature?(".png", <<0x89, "PNG\r\n", 0x1A, 0x0A, _::binary>>), do: true

  defp match_signature?(ext, <<0xFF, 0xD8, 0xFF, _::binary>>) when ext in [".jpg", ".jpeg"],
    do: true

  defp match_signature?(".webp", <<"RIFF", _::binary-size(4), "WEBP">>), do: true
  defp match_signature?(_, _), do: false
end
