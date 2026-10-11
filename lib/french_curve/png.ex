defmodule FrenchCurve.Png do
  @moduledoc """
  Encodes raw RGBA pixels as a PNG.

  `encode/3` writes truecolour with alpha, the format iTerm2's inline-image protocol
  takes. `encode_indexed/3` writes a palette image, one byte a pixel, for pictures of at
  most 256 colours such as pixel art, where it is far smaller. Encoding only; there is no
  decoder.

      png = FrenchCurve.Png.encode(width, height, FrenchCurve.Raster.to_rgba_binary(raster))
  """

  @signature <<137, 80, 78, 71, 13, 10, 26, 10>>

  @doc """
  Encodes a dense RGBA buffer as a complete PNG binary.

  `rgba` must be exactly `width * height * 4` bytes, four bytes per pixel in red, green,
  blue, alpha order and rows top to bottom; a mismatched size raises `FunctionClauseError`,
  as do non-positive dimensions.

  The result is an 8-bit-per-channel truecolour-with-alpha PNG whose scanlines all use
  filter type 0 and whose pixel data sits in a single `IDAT` chunk deflated at the fastest
  level.
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

  @doc """
  Encodes a dense RGBA buffer, as `encode/3` takes it, as a palette PNG: each distinct
  colour, alpha included, once in its `PLTE` and `tRNS` chunks, and a byte a pixel
  deflated by `FrenchCurve.Deflate` at `level` (default 6).

  Returns `{:error, :too_many_colours}` when the buffer has more than 256 colours.
  """
  @spec encode_indexed(pos_integer, pos_integer, binary, 1..12) ::
          {:ok, binary} | {:error, :too_many_colours}
  def encode_indexed(width, height, rgba, level \\ 6)
      when is_integer(width) and width > 0 and is_integer(height) and height > 0 and
             byte_size(rgba) == width * height * 4 do
    with {:ok, indices, palette} <- indexed(rgba, %{}, 0, []) do
      colours = palette |> Enum.sort_by(&elem(&1, 1)) |> Enum.map(&elem(&1, 0))

      {:ok,
       @signature <>
         chunk("IHDR", <<width::32, height::32, 8, 3, 0, 0, 0>>) <>
         chunk(
           "PLTE",
           for(<<red, green, blue, _alpha>> <- colours, into: <<>>, do: <<red, green, blue>>)
         ) <>
         transparency(colours) <>
         chunk("IDAT", FrenchCurve.Deflate.compress(filter_scanlines(indices, width), level)) <>
         chunk("IEND", <<>>)}
    end
  end

  defp indexed(<<pixel::binary-size(4), rest::binary>>, palette, count, acc) do
    case palette do
      %{^pixel => index} -> indexed(rest, palette, count, [index | acc])
      _new when count == 256 -> {:error, :too_many_colours}
      _new -> indexed(rest, Map.put(palette, pixel, count), count + 1, [count | acc])
    end
  end

  defp indexed(<<>>, palette, _count, acc),
    do: {:ok, acc |> Enum.reverse() |> :erlang.list_to_binary(), palette}

  defp transparency(colours) do
    alphas = for <<_red, _green, _blue, alpha>> <- colours, into: <<>>, do: <<alpha>>
    opaque = :binary.copy(<<255>>, byte_size(alphas))
    if alphas == opaque, do: <<>>, else: chunk("tRNS", alphas)
  end

  defp ihdr(width, height), do: <<width::32, height::32, 8, 6, 0, 0, 0>>

  defp idat(width, rgba) do
    zlib = :zlib.open()
    :ok = :zlib.deflateInit(zlib, :best_speed)
    deflated = :zlib.deflate(zlib, filter_scanlines(rgba, width * 4), :finish)
    :ok = :zlib.deflateEnd(zlib)
    :ok = :zlib.close(zlib)
    IO.iodata_to_binary(deflated)
  end

  defp filter_scanlines(pixels, stride) do
    IO.iodata_to_binary(for <<row::binary-size(^stride) <- pixels>>, do: [0, row])
  end

  defp chunk(type, data) do
    <<byte_size(data)::32>> <> type <> data <> <<:erlang.crc32(type <> data)::32>>
  end
end
