defmodule FrenchCurve.Backend.Braille do
  @moduledoc false

  import Bitwise

  alias FrenchCurve.Raster

  @braille_base 0x2800
  @dot_bits %{
    {0, 0} => 0x01,
    {0, 1} => 0x02,
    {0, 2} => 0x04,
    {0, 3} => 0x40,
    {1, 0} => 0x08,
    {1, 1} => 0x10,
    {1, 2} => 0x20,
    {1, 3} => 0x80
  }

  @type cell :: {binary, Raster.color_rgb() | nil}

  @spec render(Raster.t(), keyword) :: [[cell]]
  def render(%Raster{} = raster, opts \\ []) do
    threshold = Keyword.get(opts, :alpha_threshold, 1)
    {width, height} = Raster.dimensions(raster)
    cols = ceil_div(width, 2)
    rows = ceil_div(height, 4)

    for cy <- 0..(rows - 1) do
      for cx <- 0..(cols - 1) do
        cell(raster, cx, cy, threshold)
      end
    end
  end

  @spec to_text([[cell]]) :: [binary]
  def to_text(rows) do
    Enum.map(rows, fn row ->
      row |> Enum.map(fn {char, _color} -> char end) |> IO.iodata_to_binary()
    end)
  end

  @spec to_ansi([[cell]]) :: binary
  def to_ansi(rows) do
    Enum.map_join(rows, "\n", fn row -> Enum.map_join(row, "", &cell_to_ansi/1) end)
  end

  defp cell_to_ansi({grapheme, nil}), do: grapheme

  defp cell_to_ansi({grapheme, {r, g, b}}) do
    "\e[38;2;#{r};#{g};#{b}m" <> grapheme <> "\e[0m"
  end

  defp cell(raster, cx, cy, threshold) do
    lit =
      for {{dx, dy}, bit} <- @dot_bits,
          {r, g, b, a} = Raster.get_pixel(raster, cx * 2 + dx, cy * 4 + dy),
          a >= threshold,
          do: {bit, {r, g, b}}

    mask = Enum.reduce(lit, 0, fn {bit, _color}, acc -> bor(acc, bit) end)
    {<<@braille_base + mask::utf8>>, average_color(lit)}
  end

  defp average_color([]), do: nil

  defp average_color(lit) do
    {sr, sg, sb} =
      Enum.reduce(lit, {0, 0, 0}, fn {_bit, {r, g, b}}, {ar, ag, ab} ->
        {ar + r, ag + g, ab + b}
      end)

    count = length(lit)
    {round(sr / count), round(sg / count), round(sb / count)}
  end

  defp ceil_div(value, divisor), do: div(value + divisor - 1, divisor)
end
