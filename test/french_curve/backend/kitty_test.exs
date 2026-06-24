defmodule FrenchCurve.Backend.KittyTest do
  use ExUnit.Case, async: true

  alias FrenchCurve.Backend.Kitty
  alias FrenchCurve.Raster

  defp payload_bytes(out) do
    [_control, rest] = String.split(out, ";", parts: 2)
    rest |> String.replace_trailing("\e\\", "") |> Base.decode64!()
  end

  test "emits a transmit-and-display RGBA sequence" do
    raster =
      Raster.new(2, 2, background: {0, 0, 0, 255})
      |> Raster.put_pixel(0, 0, {255, 0, 0, 255})

    out = Kitty.render(raster)

    assert String.starts_with?(out, "\e_G")
    assert String.ends_with?(out, "\e\\")
    assert out =~ "a=T"
    assert out =~ "f=32"
    assert out =~ "s=2,v=2"
  end

  test "carries the raw RGBA buffer row-major" do
    raster =
      Raster.new(2, 1, background: {0, 0, 0, 255})
      |> Raster.put_pixel(0, 0, {255, 0, 0, 255})
      |> Raster.put_pixel(1, 0, {0, 255, 0, 255})

    assert payload_bytes(Kitty.render(raster)) == <<255, 0, 0, 255, 0, 255, 0, 255>>
  end

  test "chunks large payloads with m=1 continuations and a final m=0" do
    raster = Raster.new(64, 64, background: {1, 2, 3, 255})
    out = Kitty.render(raster)

    assert length(String.split(out, "\e_G")) - 1 > 1
    assert out =~ "m=1"
    assert out =~ "m=0"
  end

  test "fit: {cols, rows} scales the image into a cell box" do
    out = Kitty.render(Raster.new(8, 8), fit: {12, 6})
    assert out =~ "c=12,r=6"
  end

  test "omits cell placement when no fit is requested" do
    refute Kitty.render(Raster.new(8, 8)) =~ "c="
  end

  describe "sprite primitives" do
    test "transmit/2 stores an image under an id without displaying" do
      out = Kitty.transmit(Raster.new(2, 2), 7)
      assert String.starts_with?(out, "\e_G")
      assert String.ends_with?(out, "\e\\")
      assert out =~ "a=t,i=7"
      assert out =~ "f=32"
    end

    test "place/2 references an image with z-index and a cell box" do
      out = Kitty.place(7, z: 3, fit: {4, 2}, placement: 9)
      assert out =~ "a=p"
      assert out =~ "i=7"
      assert out =~ "z=3"
      assert out =~ "c=4,r=2"
      assert out =~ "p=9"
      assert out =~ "C=1"
    end

    test "delete/1 removes a placement by id" do
      out = Kitty.delete(id: 7, placement: 9)
      assert out =~ "a=d"
      assert out =~ "i=7"
      assert out =~ "p=9"
    end
  end
end
