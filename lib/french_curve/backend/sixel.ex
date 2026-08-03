defmodule FrenchCurve.Backend.Sixel do
  @moduledoc """
  Renders a raster as a sixel image, a palette-indexed DCS sequence.

  Sixel encodes six vertical pixels per character, so the image is written as horizontal
  bands six pixels tall, one pass per colour used in the band, run-length compressed.

  The format is indexed, not truecolour: the image is limited to 256 colours. Rasters with
  more are quantized by dropping low bits from each channel, as many as it takes to fit.

  Sixel has no alpha. Pixels below the alpha threshold are left unwritten and show
  whatever the terminal already had there, unless `:background` names a colour to paint
  them instead.

      IO.write(FrenchCurve.Backend.Sixel.render(raster, background: {0, 0, 0}))
  """

  import Bitwise

  alias FrenchCurve.Raster

  @band_height 6
  @sixel_base 0x3F
  @max_colors 256

  @doc """
  Returns the DCS sequence that draws `raster` at the cursor.

  ## Options

    * `:alpha_threshold` — the smallest alpha treated as an opaque pixel, default `1`.
      Pixels below it are transparent.
    * `:background` — an `{r, g, b}` tuple painted behind transparent pixels. Omitted by
      default, which leaves those pixels unwritten.
  """
  @spec render(Raster.t(), keyword) :: binary
  def render(%Raster{} = raster, opts \\ []) do
    threshold = Keyword.get(opts, :alpha_threshold, 1)
    background = Keyword.get(opts, :background)
    {width, height} = Raster.dimensions(raster)

    drawn_colors = collect_colors(raster, width, height, threshold, background)
    {palette, quantize} = build_palette(drawn_colors)
    index_of = palette |> Enum.with_index() |> Map.new()
    pixels = index_pixels(raster, width, height, threshold, background, quantize, index_of)

    intro(width, height) <>
      palette_defs(palette) <>
      encode_bands(pixels, width, height) <>
      "\e\\"
  end

  defp intro(width, height), do: "\eP0;1;0q\"1;1;#{width};#{height}"

  defp palette_defs(palette) do
    palette
    |> Enum.with_index()
    |> Enum.map_join("", fn {{r, g, b}, index} ->
      "#" <> Integer.to_string(index) <> ";2;#{to100(r)};#{to100(g)};#{to100(b)}"
    end)
  end

  defp to100(value), do: round(value * 100 / 255)

  defp encode_bands(pixels, width, height) do
    band_count = ceil_div(height, @band_height)
    Enum.map_join(0..(band_count - 1), "", &encode_band(pixels, width, &1))
  end

  defp encode_band(pixels, width, band) do
    case band_indices(pixels, width, band) do
      [] ->
        "-"

      indices ->
        indices
        |> Enum.map_join("$", &color_row(pixels, width, band, &1))
        |> Kernel.<>("-")
    end
  end

  defp band_indices(pixels, width, band) do
    set =
      for x <- 0..(width - 1),
          k <- 0..(@band_height - 1),
          index = Map.get(pixels, {x, band * @band_height + k}),
          index != nil,
          into: MapSet.new(),
          do: index

    set |> MapSet.to_list() |> Enum.sort()
  end

  defp color_row(pixels, width, band, index) do
    chars =
      for x <- 0..(width - 1), do: @sixel_base + column_bits(pixels, x, band, index)

    "#" <> Integer.to_string(index) <> run_length(chars)
  end

  defp column_bits(pixels, x, band, index) do
    Enum.reduce(0..(@band_height - 1), 0, fn k, acc ->
      lit_bit(pixels, x, band * @band_height + k, index, k, acc)
    end)
  end

  defp lit_bit(pixels, x, y, index, k, acc) do
    if Map.get(pixels, {x, y}) == index, do: bor(acc, bsl(1, k)), else: acc
  end

  defp run_length(codes) do
    codes
    |> Enum.chunk_by(& &1)
    |> Enum.map_join("", fn
      [code] -> <<code>>
      [code | _] = run -> "!" <> Integer.to_string(length(run)) <> <<code>>
    end)
  end

  defp collect_colors(raster, width, height, threshold, background) do
    for y <- 0..(height - 1),
        x <- 0..(width - 1),
        color = pixel_color(Raster.get_pixel(raster, x, y), threshold, background),
        color != nil,
        do: color
  end

  defp index_pixels(raster, width, height, threshold, background, quantize, index_of) do
    for y <- 0..(height - 1),
        x <- 0..(width - 1),
        color = pixel_color(Raster.get_pixel(raster, x, y), threshold, background),
        color != nil,
        into: %{} do
      {{x, y}, Map.fetch!(index_of, quantize.(color))}
    end
  end

  defp pixel_color({r, g, b, a}, threshold, _background) when a >= threshold, do: {r, g, b}
  defp pixel_color(_pixel, _threshold, nil), do: nil
  defp pixel_color(_pixel, _threshold, {r, g, b}), do: {r, g, b}

  defp build_palette(colors) do
    distinct = Enum.uniq(colors)

    if length(distinct) <= @max_colors do
      {distinct, & &1}
    else
      shift = fitting_shift(colors, 1)
      quantize = quantizer(shift)
      {colors |> Enum.map(quantize) |> Enum.uniq(), quantize}
    end
  end

  defp fitting_shift(_colors, shift) when shift >= 8, do: 8

  defp fitting_shift(colors, shift) do
    quantize = quantizer(shift)

    if colors |> Enum.map(quantize) |> Enum.uniq() |> length() <= @max_colors do
      shift
    else
      fitting_shift(colors, shift + 1)
    end
  end

  defp quantizer(shift) do
    fn {r, g, b} -> {band_value(r, shift), band_value(g, shift), band_value(b, shift)} end
  end

  defp band_value(value, shift), do: value |> bsr(shift) |> bsl(shift)

  defp ceil_div(value, divisor), do: div(value + divisor - 1, divisor)
end
