defmodule FrenchCurve.Png do
  @moduledoc """
  Encodes raw RGBA pixels as a PNG.

  Only what `FrenchCurve.Backend.Iterm2` needs to wrap a raster in the one image format
  iTerm2's inline-image protocol accepts. Encoding only; there is no decoder.

      png = FrenchCurve.Png.encode(width, height, FrenchCurve.Raster.to_rgba_binary(raster))
  """

  @signature <<137, 80, 78, 71, 13, 10, 26, 10>>

  @doc """
  Encodes a dense RGBA buffer as a complete PNG binary.

  `rgba` must be exactly `width * height * 4` bytes, four bytes per pixel in red, green,
  blue, alpha order and rows top to bottom; a mismatched size raises `FunctionClauseError`,
  as do non-positive dimensions.

  The result is an 8-bit-per-channel truecolour-with-alpha PNG whose scanlines all use
  filter type 0 and whose pixel data sits in a single zlib-compressed `IDAT` chunk.
  """
  @spec encode(pos_integer, pos_integer, binary) :: binary
  def encode(width, height, rgba)
      when is_integer(width) and width > 0 and is_integer(height) and height > 0 and
             byte_size(rgba) == width * height * 4 do
    @signature <>
      chunk("IHDR", ihdr(width, height)) <>
      chunk("IDAT", idat(width, rgba)) <>
      chunk("IEND", <<>>)
  end

  defp ihdr(width, height), do: <<width::32, height::32, 8, 6, 0, 0, 0>>

  defp idat(width, rgba) do
    rgba
    |> filter_scanlines(width * 4)
    |> :zlib.compress()
  end

  defp filter_scanlines(rgba, stride) do
    for <<row::binary-size(stride) <- rgba>>, into: <<>>, do: <<0>> <> row
  end

  defp chunk(type, data) do
    <<byte_size(data)::32>> <> type <> data <> <<:erlang.crc32(type <> data)::32>>
  end
end
