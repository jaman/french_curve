defmodule FrenchCurve.DrawTest do
  use ExUnit.Case, async: true

  alias FrenchCurve.{Draw, Raster}

  defp on?(raster, x, y), do: Raster.get_pixel(raster, x, y) != raster.background

  describe "fill_polygon/3" do
    test "fills a triangle, leaving the outside alone" do
      raster = Raster.new(10, 10) |> Draw.fill_polygon([{1, 1}, {8, 1}, {1, 8}], {255, 0, 0, 255})

      assert on?(raster, 2, 2)
      assert on?(raster, 4, 3)
      refute on?(raster, 8, 8)
      refute on?(raster, 7, 7)
    end

    test "fills a rectangle edge to edge" do
      raster =
        Raster.new(6, 6) |> Draw.fill_polygon([{1, 1}, {4, 1}, {4, 4}, {1, 4}], {0, 255, 0, 255})

      assert Enum.all?(for(x <- 1..4, y <- 1..4, do: on?(raster, x, y)))
      refute on?(raster, 0, 0)
      refute on?(raster, 5, 5)
    end

    test "takes fractional points" do
      raster =
        Raster.new(8, 8)
        |> Draw.fill_polygon([{3.5, 0.5}, {7.2, 3.9}, {3.5, 7.4}, {0.1, 3.9}], {0, 0, 255, 255})

      assert on?(raster, 3, 3)
      assert on?(raster, 4, 4)
    end
  end

  describe "line/4" do
    test "draws a horizontal line" do
      raster =
        Raster.new(5, 5)
        |> Draw.line({0, 2}, {4, 2}, {255, 0, 0, 255})

      assert Enum.all?(0..4, &on?(raster, &1, 2))
      refute on?(raster, 0, 0)
    end

    test "draws a vertical line" do
      raster =
        Raster.new(5, 5)
        |> Draw.line({1, 0}, {1, 4}, {0, 255, 0, 255})

      assert Enum.all?(0..4, &on?(raster, 1, &1))
    end

    test "draws a diagonal that hits both endpoints" do
      raster =
        Raster.new(5, 5)
        |> Draw.line({0, 0}, {4, 4}, {0, 0, 255, 255})

      assert on?(raster, 0, 0)
      assert on?(raster, 4, 4)
      assert on?(raster, 2, 2)
    end

    test "clips a line that runs off the buffer" do
      raster =
        Raster.new(3, 3)
        |> Draw.line({-5, 1}, {10, 1}, {1, 1, 1, 255})

      assert Enum.all?(0..2, &on?(raster, &1, 1))
    end
  end

  describe "polyline/3" do
    test "connects every point in sequence" do
      raster =
        Raster.new(6, 6)
        |> Draw.polyline([{0, 0}, {0, 5}, {5, 5}], {255, 255, 0, 255})

      assert on?(raster, 0, 0)
      assert on?(raster, 0, 5)
      assert on?(raster, 5, 5)
      assert on?(raster, 3, 5)
    end

    test "a single point still marks that pixel" do
      raster = Draw.polyline(Raster.new(3, 3), [{1, 1}], {1, 2, 3, 255})
      assert on?(raster, 1, 1)
    end
  end

  describe "rect/4 and fill_rect/4" do
    test "rect draws only the border" do
      raster = Draw.rect(Raster.new(5, 5), {1, 1}, {3, 3}, {255, 0, 0, 255})
      assert on?(raster, 1, 1)
      assert on?(raster, 3, 3)
      assert on?(raster, 2, 1)
      refute on?(raster, 2, 2)
    end

    test "fill_rect fills the interior" do
      raster = Draw.fill_rect(Raster.new(5, 5), {1, 1}, {3, 3}, {0, 255, 0, 255})

      for x <- 1..3, y <- 1..3 do
        assert on?(raster, x, y)
      end

      refute on?(raster, 0, 0)
    end
  end

  describe "circle/4" do
    test "plots points roughly one radius from the center" do
      center = {6, 6}
      radius = 4
      raster = Draw.circle(Raster.new(13, 13), center, radius, {255, 255, 255, 255})

      assert on?(raster, 6, 2)
      assert on?(raster, 6, 10)
      assert on?(raster, 2, 6)
      assert on?(raster, 10, 6)
      refute on?(raster, 6, 6)
    end
  end

  describe "fill_circle/4" do
    test "fills the interior including the center" do
      raster = Draw.fill_circle(Raster.new(11, 11), {5, 5}, 4, {255, 255, 255, 255})
      assert on?(raster, 5, 5)
      assert on?(raster, 5, 2)
      assert on?(raster, 2, 5)
      refute on?(raster, 0, 0)
    end
  end
end
