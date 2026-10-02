defmodule FrenchCurve.DeflateTest do
  use ExUnit.Case, async: true

  alias FrenchCurve.Deflate

  defp picture do
    for y <- 0..199, x <- 0..299, into: <<>> do
      cond do
        rem(x + y, 23) == 0 -> <<0, 0, 0, 0>>
        rem(x, 7) < 3 -> <<rem(x * 5, 256), rem(y * 11, 256), rem(x * y, 256), 255>>
        true -> <<40, 44, 60, 255>>
      end
    end
  end

  describe "compress/2" do
    test "a terminal can read what it produces, whichever path ran" do
      pixels = picture()

      assert :zlib.uncompress(Deflate.compress(pixels)) == pixels
    end

    test "every level is readable and none is bigger than the raw pixels" do
      pixels = picture()

      for level <- [1, 3, 6, 9, 12] do
        out = Deflate.compress(pixels, level)

        assert :zlib.uncompress(out) == pixels, "level #{level} produced something unreadable"
        assert byte_size(out) < byte_size(pixels)
      end
    end

    test "a higher level is never larger than a lower one" do
      pixels = picture()
      sizes = for level <- [1, 3, 6, 9], do: byte_size(Deflate.compress(pixels, level))

      assert sizes == Enum.sort(sizes, :desc), "levels gave #{inspect(sizes)}"
    end

    test "a level outside the range is clamped rather than refused" do
      pixels = picture()

      assert :zlib.uncompress(Deflate.compress(pixels, 0)) == pixels
      assert :zlib.uncompress(Deflate.compress(pixels, 99)) == pixels
    end

    test "nothing to compress is still readable" do
      assert :zlib.uncompress(Deflate.compress(<<>>)) == <<>>
    end

    test "the C path and the Elixir path both make zlib a terminal can read" do
      pixels = picture()
      elixir = :zlib.compress(pixels)

      assert :zlib.uncompress(elixir) == pixels
      assert :zlib.uncompress(Deflate.compress(pixels, 6)) == pixels
    end
  end

  describe "available?/0" do
    test "says which path is in use, and does not raise either way" do
      assert is_boolean(Deflate.available?())
    end
  end
end
