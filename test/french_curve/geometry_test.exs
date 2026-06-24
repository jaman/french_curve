defmodule FrenchCurve.GeometryTest do
  use ExUnit.Case, async: true

  alias FrenchCurve.Geometry

  describe "cell size detection contract" do
    test "cell_size_query/0 is the CSI 16 t request" do
      assert Geometry.cell_size_query() == "\e[16t"
    end

    test "parse_cell_size/1 reads a CSI 6;height;width t reply as {width, height}" do
      assert Geometry.parse_cell_size("\e[6;20;10t") == {:ok, {10, 20}}
    end

    test "parse_cell_size/1 finds the reply amid surrounding bytes" do
      assert Geometry.parse_cell_size("junk\e[6;18;9tmore") == {:ok, {9, 18}}
    end

    test "parse_cell_size/1 returns :error on a non-matching reply" do
      assert Geometry.parse_cell_size("\e[6;bad") == :error
      assert Geometry.parse_cell_size("") == :error
    end

    test "detect_cell_size/1 runs the host's IO function and parses the reply" do
      io = fn query ->
        assert query == "\e[16t"
        "\e[6;20;10t"
      end

      assert Geometry.detect_cell_size(io) == {:ok, {10, 20}}
    end

    test "detect_cell_size/1 returns :error when the host yields no usable reply" do
      assert Geometry.detect_cell_size(fn _query -> nil end) == :error
    end
  end

  describe "sizing a cell region to pixels" do
    test "multiplies the region by a known cell-pixel size" do
      assert Geometry.pixels_for_cells({10, 5}, {8, 16}) == {80, 80}
    end

    test "falls back to the default cell-pixel size when unknown" do
      assert Geometry.pixels_for_cells({10, 5}, :unknown) == {100, 100}
      assert Geometry.default_cell_px() == {10, 20}
    end

    test "braille has a fixed 2x4 cell, independent of the terminal" do
      assert Geometry.braille_cell_px() == {2, 4}
      assert Geometry.pixels_for_cells({40, 10}, Geometry.braille_cell_px()) == {80, 40}
    end
  end
end
