defmodule Dcomp.DecompTest do
  use Dcomp.DataCase, async: true

  alias Dcomp.Decomp

  describe "settings" do
    test "get_settings/0 creates defaults once" do
      s = Decomp.get_settings()
      assert s.poll_interval_s == 300
      assert s.layout_mode == :size
      assert Decomp.get_settings().id == s.id
    end

    test "update_settings/2 validates the poll interval and layout mode" do
      s = Decomp.get_settings()
      assert {:ok, s} = Decomp.update_settings(s, %{poll_interval_s: 60, layout_mode: :grid})
      assert {s.poll_interval_s, s.layout_mode} == {60, :grid}
      assert {:error, cs} = Decomp.update_settings(s, %{poll_interval_s: 5})
      assert %{poll_interval_s: [_]} = errors_on(cs)
      assert {:error, cs} = Decomp.update_settings(s, %{poll_interval_s: 9_999_999})
      assert %{poll_interval_s: [_]} = errors_on(cs)
      assert {:error, _} = Decomp.update_settings(s, %{layout_mode: "bogus"})
    end
  end

  describe "api key" do
    test "no key is valid before one is generated" do
      refute Decomp.valid_api_key?("anything")
      refute Decomp.valid_api_key?(nil)
    end

    test "rotate_api_key/0 returns a working key and invalidates the old one" do
      {:ok, k1} = Decomp.rotate_api_key()
      assert Decomp.valid_api_key?(k1)
      refute Decomp.valid_api_key?(k1 <> "x")
      refute Decomp.get_settings().api_key_hash == k1

      {:ok, k2} = Decomp.rotate_api_key()
      refute Decomp.valid_api_key?(k1)
      assert Decomp.valid_api_key?(k2)
    end
  end

  describe "games" do
    @valid %{
      name: "Drill Dozer",
      repo_url: "https://github.com/TrashSlopStudio/drill-dozer-decomp"
    }

    test "create_game/1 derives the slug and defaults the branch" do
      assert {:ok, g} = Decomp.create_game(@valid)
      assert g.slug == "drill-dozer"
      assert g.branch == "main"
      assert Decomp.get_game_by_slug!("drill-dozer").id == g.id
    end

    test "slugs are unique" do
      {:ok, _} = Decomp.create_game(@valid)
      assert {:error, cs} = Decomp.create_game(@valid)
      assert %{slug: ["has already been taken"]} = errors_on(cs)
    end

    test "rom_sha1 is normalised and must be 40 hex characters" do
      sha = String.duplicate("AB", 20)
      attrs = %{name: "G", repo_url: "https://example.com/o/r"}

      assert {:ok, game} = Decomp.create_game(Map.put(attrs, :rom_sha1, " " <> sha <> " "))
      assert game.rom_sha1 == String.downcase(sha)
      assert {:error, cs} = Decomp.create_game(%{attrs | name: "H"} |> Map.put(:rom_sha1, "xyz"))
      assert %{rom_sha1: [_]} = errors_on(cs)
    end

    test "delete_game/1 removes the local mirror" do
      {:ok, game} = Decomp.create_game(%{name: "Gone", repo_url: "https://example.com/o/r"})
      dir = Dcomp.Decomp.Mirror.dir(game)
      File.mkdir_p!(dir)

      assert {:ok, _} = Decomp.delete_game(game)
      refute File.exists?(dir)
    end

    test "repo_url must be https (git clones it)" do
      for url <- ["file:///etc", "git@github.com:a/b.git", "ext::sh -c id", "http://x.io/a"] do
        assert {:error, cs} = Decomp.create_game(%{@valid | repo_url: url})
        assert %{repo_url: [_]} = errors_on(cs)
      end
    end

    test "rules and sync state cannot be set through the form changeset" do
      {:ok, g} = Decomp.create_game(Map.merge(@valid, %{claim_hours: 1, last_synced_sha: "abc"}))
      assert g.claim_hours == nil
      assert g.last_synced_sha == nil
    end
  end
end
