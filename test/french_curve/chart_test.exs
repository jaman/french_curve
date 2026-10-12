defmodule FrenchCurve.ChartTest do
  use ExUnit.Case, async: true

  alias FrenchCurve.{Chart, Raster}

  defp on?(raster, x, y), do: Raster.get_pixel(raster, x, y) != raster.background

  test "plots data extremes at the corners" do
    raster = Chart.line([0, 1, 2, 3], width: 4, height: 4, color: {255, 0, 0, 255})
    assert Raster.dimensions(raster) == {4, 4}
    assert on?(raster, 0, 3)
    assert on?(raster, 3, 0)
  end

  test "empty values yields a blank raster of the requested size" do
    raster = Chart.line([], width: 10, height: 5)
    assert Raster.dimensions(raster) == {10, 5}
    assert raster.pixels == %{}
  end

  test "a flat series does not divide by zero" do
    raster = Chart.line([5, 5, 5], width: 6, height: 4)
    assert Raster.dimensions(raster) == {6, 4}
  end

  test "smoothing still produces a raster of the requested size" do
    raster = Chart.line([0, 3, 1, 4, 2], width: 20, height: 8, smooth: true)
    assert Raster.dimensions(raster) == {20, 8}
    assert Enum.any?(List.flatten(Raster.rows(raster)), &(&1 != {0, 0, 0, 0}))
  end

  describe "area/2" do
    defp column_height(raster, x, height) do
      Enum.count(0..(height - 1), fn y -> on?(raster, x, y) end)
    end

    test "fills more beneath high columns than low ones" do
      raster = Chart.area([0, 2, 1, 3], width: 8, height: 8, color: {0, 200, 255, 255})
      assert column_height(raster, 7, 8) > column_height(raster, 0, 8)
    end

    test "uses a dimmer fill color beneath the bright line" do
      raster =
        Chart.area([1, 4, 2, 5],
          width: 10,
          height: 8,
          color: {0, 200, 255, 255},
          fill_opacity: 0.4
        )

      colors = raster |> Raster.rows() |> List.flatten() |> Enum.uniq()
      assert {0, 200, 255, 255} in colors
      assert {0, 80, 102, 255} in colors
    end

    test "empty values yields a blank raster" do
      assert Chart.area([], width: 6, height: 4).pixels == %{}
    end
  end
end
