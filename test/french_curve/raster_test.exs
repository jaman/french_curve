defmodule FrenchCurve.RasterTest do
  use ExUnit.Case, async: true

  alias FrenchCurve.Raster

  describe "new/3" do
    test "creates a raster with the given dimensions" do
      assert Raster.dimensions(Raster.new(10, 5)) == {10, 5}
    end

    test "defaults every pixel to transparent black" do
      assert Raster.get_pixel(Raster.new(3, 3), 0, 0) == {0, 0, 0, 0}
    end

    test "accepts a custom background" do
      raster = Raster.new(3, 3, background: {10, 20, 30, 255})
      assert Raster.get_pixel(raster, 1, 1) == {10, 20, 30, 255}
    end

    test "rejects non-positive dimensions" do
      assert_raise FunctionClauseError, fn -> Raster.new(0, 4) end
      assert_raise FunctionClauseError, fn -> Raster.new(4, -1) end
    end
  end

  describe "put_pixel/4" do
    test "sets a pixel that can be read back" do
      raster = Raster.put_pixel(Raster.new(4, 4), 2, 1, {255, 0, 0, 255})
      assert Raster.get_pixel(raster, 2, 1) == {255, 0, 0, 255}
    end

    test "leaves other pixels at the background" do
      raster = Raster.put_pixel(Raster.new(4, 4), 2, 1, {255, 0, 0, 255})
      assert Raster.get_pixel(raster, 0, 0) == {0, 0, 0, 0}
    end

    test "ignores writes outside the bounds" do
      raster = Raster.new(2, 2)
      assert Raster.put_pixel(raster, -1, 0, {1, 2, 3, 4}) == raster
      assert Raster.put_pixel(raster, 0, 5, {1, 2, 3, 4}) == raster
      assert Raster.put_pixel(raster, 2, 0, {1, 2, 3, 4}) == raster
    end
  end

  describe "in_bounds?/3" do
    test "is true inside and false outside" do
      raster = Raster.new(3, 3)
      assert Raster.in_bounds?(raster, 0, 0)
      assert Raster.in_bounds?(raster, 2, 2)
      refute Raster.in_bounds?(raster, 3, 0)
      refute Raster.in_bounds?(raster, 0, -1)
    end
  end

  describe "from_rgba/4" do
    test "loads pixels row-major from a raw RGBA buffer" do
      binary = <<255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 10, 20, 30, 40>>
      raster = Raster.from_rgba(2, 2, binary)

      assert Raster.dimensions(raster) == {2, 2}
      assert Raster.get_pixel(raster, 0, 0) == {255, 0, 0, 255}
      assert Raster.get_pixel(raster, 1, 0) == {0, 255, 0, 255}
      assert Raster.get_pixel(raster, 0, 1) == {0, 0, 255, 255}
      assert Raster.get_pixel(raster, 1, 1) == {10, 20, 30, 40}
    end

    test "round-trips with to_rgba_binary/1" do
      raster =
        Raster.new(3, 2)
        |> Raster.put_pixel(0, 0, {255, 0, 0, 255})
        |> Raster.put_pixel(2, 1, {1, 2, 3, 4})

      binary = Raster.to_rgba_binary(raster)
      assert Raster.to_rgba_binary(Raster.from_rgba(3, 2, binary)) == binary
    end

    test "is binary-backed: reads pixels from the cached buffer with an empty pixel map" do
      raster = Raster.from_rgba(3, 1, <<0, 0, 0, 0, 5, 6, 7, 8, 0, 0, 0, 0>>)

      assert Raster.get_pixel(raster, 0, 0) == {0, 0, 0, 0}
      assert Raster.get_pixel(raster, 1, 0) == {5, 6, 7, 8}
      assert raster.pixels == %{}
      assert is_binary(raster.rgba)
    end

    test "rejects a buffer whose size does not match the dimensions" do
      assert_raise FunctionClauseError, fn -> Raster.from_rgba(2, 2, <<0, 0, 0, 0>>) end
    end
  end

  describe "crop/3" do
    test "keeps the rectangle from the offset, in either representation" do
      raster =
        Raster.new(4, 3)
        |> Raster.put_pixel(1, 1, {1, 0, 0, 255})
        |> Raster.put_pixel(3, 2, {2, 0, 0, 255})

      for source <- [raster, Raster.finalize(raster)] do
        cropped = Raster.crop(source, {1, 1}, {3, 2})
        assert Raster.dimensions(cropped) == {3, 2}
        assert Raster.get_pixel(cropped, 0, 0) == {1, 0, 0, 255}
        assert Raster.get_pixel(cropped, 2, 1) == {2, 0, 0, 255}
        assert Raster.get_pixel(cropped, 1, 0) == {0, 0, 0, 0}
      end
    end
  end

  describe "finalize/1 and the dense cache" do
    test "finalize caches to_rgba_binary, returning an identical buffer" do
      raster = Raster.put_pixel(Raster.new(3, 2), 0, 0, {255, 0, 0, 255})
      finalized = Raster.finalize(raster)

      assert is_binary(finalized.rgba)
      assert Raster.to_rgba_binary(finalized) == Raster.to_rgba_binary(raster)
    end

    test "drawing after finalize invalidates the cache and stays correct" do
      raster = Raster.new(2, 1) |> Raster.put_pixel(0, 0, {1, 2, 3, 4}) |> Raster.finalize()
      assert is_binary(raster.rgba)

      updated = Raster.put_pixel(raster, 1, 0, {9, 9, 9, 9})
      assert updated.rgba == nil
      assert Raster.get_pixel(updated, 0, 0) == {1, 2, 3, 4}
      assert Raster.get_pixel(updated, 1, 0) == {9, 9, 9, 9}
    end

    test "drawing on a binary-backed raster materializes prior pixels" do
      raster = Raster.from_rgba(2, 1, <<10, 20, 30, 40, 50, 60, 70, 80>>)
      updated = Raster.put_pixel(raster, 0, 0, {1, 1, 1, 1})

      assert Raster.get_pixel(updated, 0, 0) == {1, 1, 1, 1}
      assert Raster.get_pixel(updated, 1, 0) == {50, 60, 70, 80}
    end
  end
end
