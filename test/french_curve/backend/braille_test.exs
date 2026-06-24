defmodule FrenchCurve.Backend.BrailleTest do
  use ExUnit.Case, async: true

  alias FrenchCurve.Backend.Braille
  alias FrenchCurve.{Draw, Raster}

  defp braille(mask), do: <<0x2800 + mask::utf8>>

  test "reports ceil dimensions in cells" do
    rows = Braille.render(Raster.new(4, 8))
    assert length(rows) == 2
    assert length(hd(rows)) == 2
  end

  test "a single top-left pixel lights dot 1" do
    raster = Raster.put_pixel(Raster.new(2, 4), 0, 0, {10, 20, 30, 255})
    [[cell | _] | _] = Braille.render(raster)
    assert cell == {braille(0x01), {10, 20, 30}}
  end

  test "a full 2x4 block lights every dot" do
    raster = Draw.fill_rect(Raster.new(2, 4), {0, 0}, {1, 3}, {255, 255, 255, 255})
    assert [[{char, {255, 255, 255}}]] = Braille.render(raster)
    assert char == braille(0xFF)
  end

  test "empty cells are blank braille with no color" do
    assert [[{char, nil}]] = Braille.render(Raster.new(2, 4))
    assert char == braille(0x00)
  end

  test "cell color averages the lit pixels" do
    raster =
      Raster.new(2, 4)
      |> Raster.put_pixel(0, 0, {255, 0, 0, 255})
      |> Raster.put_pixel(1, 0, {0, 0, 255, 255})

    assert [[{_char, {128, 0, 128}}]] = Braille.render(raster)
  end

  test "to_text/1 returns plain line strings" do
    raster = Raster.put_pixel(Raster.new(2, 4), 0, 0, {1, 1, 1, 255})
    assert Braille.to_text(Braille.render(raster)) == [braille(0x01)]
  end

  test "to_ansi/1 wraps colored cells in 24-bit escapes and leaves blanks bare" do
    raster = Raster.put_pixel(Raster.new(4, 4), 0, 0, {10, 20, 30, 255})
    ansi = Braille.to_ansi(Braille.render(raster))

    assert ansi =~ "\e[38;2;10;20;30m" <> braille(0x01) <> "\e[0m"
    assert ansi =~ braille(0x00)
  end
end
