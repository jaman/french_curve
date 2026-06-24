defmodule FrenchCurve.Backend.SixelTest do
  use ExUnit.Case, async: true

  alias FrenchCurve.Backend.Sixel
  alias FrenchCurve.{Draw, Raster}

  defp palette_count(out), do: length(String.split(out, ";2;")) - 1

  test "wraps output in a sixel DCS string" do
    raster = Raster.put_pixel(Raster.new(1, 1), 0, 0, {255, 0, 0, 255})
    out = Sixel.render(raster)

    assert String.starts_with?(out, "\eP")
    assert String.ends_with?(out, "\e\\")
    assert out =~ "\"1;1;1;1"
  end

  test "defines the palette in 0..100 RGB and selects it" do
    raster = Raster.put_pixel(Raster.new(1, 1), 0, 0, {255, 0, 0, 255})
    out = Sixel.render(raster)

    assert out =~ "#0;2;100;0;0"
    assert out =~ "#0@"
  end

  test "run-length encodes repeated columns" do
    raster = Draw.fill_rect(Raster.new(4, 1), {0, 0}, {3, 0}, {255, 0, 0, 255})
    assert Sixel.render(raster) =~ "!4@"
  end

  test "leaves transparent columns unset" do
    raster = Raster.put_pixel(Raster.new(2, 1), 0, 0, {255, 0, 0, 255})
    assert Sixel.render(raster) =~ "@?"
  end

  test "without a background, transparent pixels add no color to the palette" do
    raster = Raster.put_pixel(Raster.new(2, 1), 0, 0, {255, 0, 0, 255})
    refute Sixel.render(raster) =~ ";2;0;0;100"
  end

  test "background option composites transparent pixels onto a solid color" do
    raster = Raster.put_pixel(Raster.new(2, 1), 0, 0, {255, 0, 0, 255})
    out = Sixel.render(raster, background: {0, 0, 255})
    assert out =~ ";2;100;0;0"
    assert out =~ ";2;0;0;100"
  end

  test "quantizes to at most 256 palette entries" do
    raster =
      Enum.reduce(0..299, Raster.new(300, 1), fn i, acc ->
        Raster.put_pixel(acc, i, 0, {rem(i, 256), div(i, 256), 0, 255})
      end)

    out = Sixel.render(raster)
    assert palette_count(out) <= 256
    assert String.starts_with?(out, "\eP")
    assert String.ends_with?(out, "\e\\")
  end
end
