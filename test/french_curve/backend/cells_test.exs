defmodule FrenchCurve.Backend.CellsTest do
  use ExUnit.Case, async: true

  import Bitwise

  alias FrenchCurve.Backend.Cells
  alias FrenchCurve.Raster

  doctest Cells

  defp block(set, pattern, lit \\ {255, 255, 255, 255}, unlit \\ {0, 0, 0, 255}) do
    {sx, sy} = Cells.subpixels(set)

    for index <- 0..(sx * sy - 1), reduce: Raster.new(sx, sy, background: unlit) do
      raster ->
        if (pattern >>> index &&& 1) == 1,
          do: Raster.put_pixel(raster, rem(index, sx), div(index, sx), lit),
          else: raster
    end
  end

  test "reports ceil dimensions in cells for every set" do
    for set <- Cells.sets() do
      {sx, sy} = Cells.subpixels(set)
      rows = Cells.render(Raster.new(sx * 2 + 1, sy * 3 + 1), set: set)
      assert length(rows) == 4, "#{set} rows"
      assert length(hd(rows)) == 3, "#{set} columns"
    end
  end

  test "a lit pattern comes back as that pattern's glyph in the lit and unlit colours" do
    for set <- Cells.sets(),
        {sx, sy} = Cells.subpixels(set),
        pattern <- 1..((1 <<< (sx * sy)) - 2) do
      [[{glyph, fg, bg}]] = Cells.render(block(set, pattern), set: set)
      assert glyph == Cells.glyph(set, pattern), "#{set} pattern #{pattern}"
      assert fg == {255, 255, 255}
      assert bg == {0, 0, 0}
    end
  end

  test "a cell of one colour is a space on that colour" do
    assert [[{" ", {40, 50, 60}, {40, 50, 60}}]] =
             Cells.render(Raster.new(2, 3, background: {40, 50, 60, 255}), set: :sextant)
  end

  test "half blocks keep both colours exactly" do
    raster =
      Raster.new(1, 2)
      |> Raster.put_pixel(0, 0, {200, 10, 10, 255})
      |> Raster.put_pixel(0, 1, {10, 10, 200, 255})

    assert [[{"▀", {200, 10, 10}, {10, 10, 200}}]] = Cells.render(raster, set: :half)
  end

  test "each group takes the mean of its pixels" do
    raster =
      Raster.new(2, 2)
      |> Raster.put_pixel(0, 0, {250, 250, 250, 255})
      |> Raster.put_pixel(1, 0, {230, 230, 230, 255})
      |> Raster.put_pixel(0, 1, {20, 20, 20, 255})
      |> Raster.put_pixel(1, 1, {0, 0, 0, 255})

    assert [[{"▀", {240, 240, 240}, {10, 10, 10}}]] = Cells.render(raster, set: :quad)
  end

  test "transparent pixels and pixels past the edge take the background" do
    raster = Raster.put_pixel(Raster.new(1, 1), 0, 0, {255, 255, 255, 255})

    assert [[{"▀", {255, 255, 255}, {9, 9, 9}}]] =
             Cells.render(raster, set: :half, background: {9, 9, 9})

    assert [[{" ", {9, 9, 9}, {9, 9, 9}}]] =
             Cells.render(Raster.new(1, 2), set: :half, background: {9, 9, 9})
  end

  test "the octant table uses the Unicode 16 block for every pattern without an older glyph" do
    named =
      for pattern <- 0..255,
          <<code::utf8>> = Cells.glyph(:octant, pattern),
          code >= 0x1CD00 and code <= 0x1CDE5,
          do: code

    assert length(named) == 230
    assert Enum.sort(named) == Enum.to_list(0x1CD00..0x1CDE5)
  end

  test "the sextant table uses every Unicode 13 sextant once" do
    codes =
      for pattern <- 0..63,
          <<code::utf8>> = Cells.glyph(:sextant, pattern),
          code >= 0x1FB00 and code <= 0x1FB3B,
          do: code

    assert Enum.sort(codes) == Enum.to_list(0x1FB00..0x1FB3B)
    assert Cells.glyph(:sextant, 0b010101) == "▌"
    assert Cells.glyph(:sextant, 0b101010) == "▐"
  end

  test "to_ansi colours every glyph and resets each row" do
    ansi = Cells.to_ansi([[{"▀", {1, 2, 3}, {4, 5, 6}}]])
    assert ansi == "\e[38;2;1;2;3m\e[48;2;4;5;6m▀\e[0m"
  end

  test "the dispatch reaches the backend" do
    assert [[{" ", _, _}]] = FrenchCurve.render(Raster.new(1, 2), :cells, [])
    assert is_binary(FrenchCurve.to_terminal(Raster.new(1, 2), :cells, set: :half))
    assert FrenchCurve.frame(Raster.new(1, 2), :any, protocol: :cells) == nil
  end
end
