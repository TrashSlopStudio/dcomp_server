defmodule Dcomp.Decomp.UploadsTest do
  use ExUnit.Case, async: true

  alias Dcomp.Decomp.Uploads

  @tmp System.tmp_dir!()

  defp file!(content) do
    path = Path.join(@tmp, "upload_src_#{System.unique_integer([:positive])}")
    File.write!(path, content)
    on_exit(fn -> File.rm(path) end)
    path
  end

  test "stores real images under a random name with the whitelisted extension" do
    cases = [
      {".png", <<0x89, "PNG\r\n", 0x1A, 0x0A, 0, 0>>},
      {".JPG", <<0xFF, 0xD8, 0xFF, 0xE0, 0, 0>>},
      {".jpeg", <<0xFF, 0xD8, 0xFF, 0xE0, 0, 0>>},
      {".webp", <<"RIFF", 1, 2, 3, 4, "WEBP", "VP8 ">>}
    ]

    for {ext, bytes} <- cases do
      assert {:ok, name} = Uploads.save(file!(bytes), "my cover" <> ext)
      assert name =~ ~r/\A[0-9a-f-]{36}\.(png|jpe?g|webp)\z/
      assert File.read!(Uploads.path(name)) == bytes
      Uploads.delete(name)
      refute File.exists?(Uploads.path(name))
    end
  end

  test "rejects content that doesn't match its extension, and other extensions" do
    assert {:error, :bad_type} = Uploads.save(file!("<svg onload=alert(1)>"), "a.png")
    assert {:error, :bad_type} = Uploads.save(file!(<<0xFF, 0xD8, 0xFF, 0>>), "a.png")
    assert {:error, :bad_type} = Uploads.save(file!(<<0x89, "PNG\r\n", 0x1A, 0x0A>>), "a.svg")
    assert {:error, :bad_type} = Uploads.save(file!(<<0x89, "PNG\r\n", 0x1A, 0x0A>>), "a.html")
    assert {:error, :bad_type} = Uploads.save(file!(""), "a.png")
  end

  test "path/1 and delete/1 only touch names we generate" do
    assert Uploads.path("../../etc/passwd") == nil
    assert Uploads.path("evil.png") == nil
    assert Uploads.path(nil) == nil
    assert :ok = Uploads.delete("../../etc/passwd")
    assert :ok = Uploads.delete(nil)
  end
end
