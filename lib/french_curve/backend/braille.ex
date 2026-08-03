defmodule FrenchCurve.Backend.Braille do
  @moduledoc """
  Renders a raster as braille characters, for terminals with no graphics protocol at all.

  Each braille character carries eight dots in a 2-wide by 4-tall grid, so one cell stands
  in for a 2-by-4 block of pixels and a raster comes out at `ceil(width / 2)` columns by
  `ceil(height / 4)` rows. A pixel is a lit dot when its alpha reaches the threshold;
  colour is per character, averaged over that cell's lit pixels, so detail below one cell
  survives in shape but not in colour.

  `render/2` returns cell rows and `to_ansi/1` or `to_text/1` turn those into a string.

      raster
      |> FrenchCurve.Backend.Braille.render()
      |> FrenchCurve.Backend.Braille.to_ansi()
      |> IO.puts()
  """

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

  @typedoc """
  One character cell: the braille grapheme, and the average RGB of its lit pixels or `nil`
  when no pixel in the cell was lit.
  """
  @type cell :: {binary, Raster.color_rgb() | nil}

  @doc """
  Renders `raster` as rows of `t:cell/0`, top row first.

  Returns `ceil(height / 4)` rows of `ceil(width / 2)` cells. Cells at the right and
  bottom edges read pixels past the raster bounds, which come back as the background and
  so are lit only if the background itself passes the threshold.

  ## Options

    * `:alpha_threshold` — the smallest alpha counted as a lit dot, default `1`. Raise it
      to drop faint pixels; `0` lights every pixel including fully transparent ones.
  """
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

  @doc """
  Flattens cell rows to one uncoloured string per row, dropping the colours.

  Returns a list of binaries, one per row, each of braille characters only.
  """
  @spec to_text([[cell]]) :: [binary]
  def to_text(rows) do
    Enum.map(rows, fn row ->
      row |> Enum.map(fn {char, _color} -> char end) |> IO.iodata_to_binary()
    end)
  end

  @doc """
  Flattens cell rows to a single newline-separated string with 24-bit colour.

  Each coloured cell is wrapped in a truecolour foreground sequence and reset immediately
  after, so the string leaves no styling behind. Cells with no lit pixels are emitted bare.
  Rows are joined with `\\n` and there is no trailing newline.
  """
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
