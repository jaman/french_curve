defmodule FrenchCurve.CurveTest do
  use ExUnit.Case, async: true

  alias FrenchCurve.Curve

  defp close?({x1, y1}, {x2, y2}), do: abs(x1 - x2) < 1.0e-6 and abs(y1 - y2) < 1.0e-6

  describe "catmull_rom/2" do
    test "passes through every control point" do
      points = [{0.0, 0.0}, {2.0, 4.0}, {5.0, 1.0}, {8.0, 6.0}]
      out = Curve.catmull_rom(points, samples: 8)

      for p <- points do
        assert Enum.any?(out, &close?(&1, p))
      end
    end

    test "keeps collinear points on the line" do
      points = [{0.0, 0.0}, {2.0, 2.0}, {4.0, 4.0}, {6.0, 6.0}]
      out = Curve.catmull_rom(points, samples: 10)
      assert Enum.all?(out, fn {x, y} -> abs(x - y) < 1.0e-6 end)
    end

    test "more samples yields more points" do
      points = [{0.0, 0.0}, {1.0, 2.0}, {2.0, 0.0}]

      assert length(Curve.catmull_rom(points, samples: 20)) >
               length(Curve.catmull_rom(points, samples: 4))
    end

    test "fewer than two points returns the input unchanged" do
      assert Curve.catmull_rom([{1.0, 1.0}], samples: 8) == [{1.0, 1.0}]
      assert Curve.catmull_rom([], samples: 8) == []
    end
  end

  describe "to_pixels/1" do
    test "rounds floats to integer coordinates" do
      assert Curve.to_pixels([{0.4, 1.6}, {2.5, 3.49}]) == [{0, 2}, {3, 3}]
    end
  end
end
