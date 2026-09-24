defmodule FrenchCurve.Backend.CellsNativeTest do
  use ExUnit.Case, async: true

  alias FrenchCurve.Backend.Cells
  alias FrenchCurve.Raster

  @width 37
  @height 23

  defp busy do
    rgba =
      for y <- 0..(@height - 1), x <- 0..(@width - 1), into: <<>> do
        cond do
          rem(x + y, 11) == 0 -> <<0, 0, 0, 0>>
          x < 3 or y < 2 -> <<255, 255, 255, 255>>
          rem(x, 5) < 2 -> <<rem(x * 7, 256), rem(y * 13, 256), rem(x * y, 256), 255>>
          true -> <<rem(y * 3, 256), 200, rem(x * 11, 256), 200>>
        end
      end

    Raster.from_rgba(@width, @height, rgba)
  end

  defp rendered(set, opts),
    do: Cells.render(busy(), [set: set, background: {12, 14, 20}] ++ opts)

  describe "the C quantiser and the Elixir one" do
    test "the library is built, so the two are being compared" do
      assert Cells.available?()
    end

    for set <- [:half, :quad, :sextant, :octant] do
      test "agree on #{set}" do
        native = rendered(unquote(set), native: true)
        elixir = rendered(unquote(set), native: false)

        assert native == elixir
      end
    end

    test "agree on a picture that is entirely transparent" do
      blank = Raster.new(@width, @height, background: {0, 0, 0, 0})

      for set <- [:half, :quad, :sextant, :octant] do
        assert Cells.render(blank, set: set, native: true) ==
                 Cells.render(blank, set: set, native: false)
      end
    end

    test "agree on a picture smaller than one cell" do
      speck = Raster.new(1, 1, background: {200, 30, 90, 255})

      for set <- [:half, :quad, :sextant, :octant] do
        assert Cells.render(speck, set: set, native: true) ==
                 Cells.render(speck, set: set, native: false)
      end
    end
  end
end
