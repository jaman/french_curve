defmodule FrenchCurve.SpriteTest do
  use ExUnit.Case, async: true

  alias FrenchCurve.{Raster, Sprite}
  alias FrenchCurve.Sprite.Registry

  defp sample, do: Raster.put_pixel(Raster.new(4, 4), 1, 1, {255, 0, 0, 255})

  describe "new/2" do
    test "derives a stable content id and records dimensions" do
      a = Sprite.new(sample())
      b = Sprite.new(sample())
      assert a.id == b.id
      assert {a.width, a.height} == {4, 4}
    end

    test "distinguishes different content" do
      a = Sprite.new(sample())
      b = Sprite.new(Raster.put_pixel(Raster.new(4, 4), 2, 2, {0, 255, 0, 255}))
      refute a.id == b.id
    end
  end

  describe "upload/2" do
    test "is a kitty transmit, empty for every other backend" do
      sprite = Sprite.new(sample(), id: 7)
      assert Sprite.upload(sprite, :kitty) =~ "a=t,i=7"
      assert Sprite.upload(sprite, :sixel) == ""
      assert Sprite.upload(sprite, :iterm2) == ""
      assert Sprite.upload(sprite, :braille) == ""
    end
  end

  describe "place/3" do
    test "kitty references the uploaded image" do
      assert Sprite.place(Sprite.new(sample(), id: 7), :kitty, z: 1) =~ "a=p"
    end

    test "pixel fallbacks re-emit the sprite pixels" do
      sprite = Sprite.new(sample())
      assert String.starts_with?(Sprite.place(sprite, :sixel, []), "\eP")
      assert String.starts_with?(Sprite.place(sprite, :iterm2, []), "\e]1337")
    end

    test "braille renders the sprite as colored cells" do
      assert Sprite.place(Sprite.new(sample()), :braille, []) =~ ~r/[\x{2800}-\x{28FF}]/u
    end
  end

  describe "delete/3" do
    test "kitty deletes a placement, other backends are no-ops" do
      sprite = Sprite.new(sample(), id: 7)
      assert Sprite.delete(sprite, :kitty, placement: 3) =~ "a=d"
      assert Sprite.delete(sprite, :sixel, []) == ""
    end
  end

  describe "Registry" do
    test "uploads a kitty sprite once, then yields nothing" do
      sprite = Sprite.new(sample(), id: 7)
      registry = Registry.new()

      {registry, first} = Registry.ensure(registry, sprite, :kitty)
      {_registry, second} = Registry.ensure(registry, sprite, :kitty)

      assert first =~ "a=t,i=7"
      assert second == ""
    end

    test "never uploads for non-kitty protocols" do
      {_registry, bytes} = Registry.ensure(Registry.new(), Sprite.new(sample()), :sixel)
      assert bytes == ""
    end
  end
end
