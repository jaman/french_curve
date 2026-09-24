defmodule FrenchCurve.Backend.Cells do
  @moduledoc """
  Renders a raster as block characters, two colours per cell, for terminals with no
  graphics protocol.

  A cell stands in for a small block of pixels, sized by the glyph `:set`:

    * `:half` — 1×2, `▀` and `▄`; every terminal and font
    * `:quad` — 2×2, the sixteen quadrant blocks
    * `:sextant` — 2×3, the sixty Unicode 13 sextants with `▌`, `▐` and `█`
    * `:braille` — 2×4 dots; dots do not fill the cell, so the background shows
      through around them
    * `:octant` — 2×4, the 230 Unicode 16 octants with the 24 patterns that are
      older block characters; solid, and the finest of the sets

  The pixels of a cell are split into two groups, those nearer the brightest pixel and
  those nearer the darkest. The first group is drawn in the foreground colour, the mean
  of its pixels, as the glyph whose pattern they form; the rest is the background, the
  mean of the other pixels. A cell of one colour is a space on that background.

  A raster `width` by `height` comes out at `ceil(width / sx)` columns by
  `ceil(height / sy)` rows for a set of `sx` by `sy` pixels. Pixels past the raster's
  edge, and pixels below the alpha threshold, take the `:background` colour.

  `render/2` returns cell rows; `to_ansi/1` turns them into a string.

      raster
      |> FrenchCurve.Backend.Cells.render(set: :sextant)
      |> FrenchCurve.Backend.Cells.to_ansi()
      |> IO.puts()
  """

  import Bitwise

  @on_load :load_nif

  alias FrenchCurve.{Capability, Raster}

  @typedoc "A glyph with its foreground and background colours."
  @type cell :: {binary, Raster.color_rgb(), Raster.color_rgb()}

  @typedoc "A glyph set."
  @type set :: :half | :quad | :sextant | :braille | :octant

  @sets [:half, :quad, :sextant, :braille, :octant]
  @subpixels %{half: {1, 2}, quad: {2, 2}, sextant: {2, 3}, braille: {2, 4}, octant: {2, 4}}
  @quadrants [" " | ~w(▘ ▝ ▀ ▖ ▌ ▞ ▛ ▗ ▚ ▐ ▜ ▄ ▙ ▟ █)]
  @octant_elsewhere %{
    0 => 0x20,
    1 => 0x1CEA8,
    2 => 0x1CEAB,
    3 => 0x1FB82,
    5 => 0x2598,
    10 => 0x259D,
    15 => 0x2580,
    20 => 0x1FBE6,
    40 => 0x1FBE7,
    63 => 0x1FB85,
    64 => 0x1CEA3,
    80 => 0x2596,
    85 => 0x258C,
    90 => 0x259E,
    95 => 0x259B,
    128 => 0x1CEA0,
    160 => 0x2597,
    165 => 0x259A,
    170 => 0x2590,
    175 => 0x259C,
    192 => 0x2582,
    240 => 0x2584,
    245 => 0x2599,
    250 => 0x259F,
    252 => 0x2586,
    255 => 0x2588
  }
  @octants 0..255
           |> Enum.reduce({%{}, 0}, fn pattern, {glyphs, next} ->
             case Map.fetch(@octant_elsewhere, pattern) do
               {:ok, code} -> {Map.put(glyphs, pattern, <<code::utf8>>), next}
               :error -> {Map.put(glyphs, pattern, <<0x1CD00 + next::utf8>>), next + 1}
             end
           end)
           |> elem(0)
  @sextants Map.new(0..63, fn
              0 -> {0, " "}
              21 -> {21, "▌"}
              42 -> {42, "▐"}
              63 -> {63, "█"}
              pattern when pattern < 21 -> {pattern, <<0x1FB00 + pattern - 1::utf8>>}
              pattern when pattern < 42 -> {pattern, <<0x1FB00 + pattern - 2::utf8>>}
              pattern -> {pattern, <<0x1FB00 + pattern - 3::utf8>>}
            end)
  @braille_bits {0x01, 0x08, 0x02, 0x10, 0x04, 0x20, 0x40, 0x80}

  @doc "The glyph sets, coarsest first."
  @spec sets() :: [set]
  def sets, do: @sets

  @doc """
  How many pixels across and down one cell of `set` covers.

      iex> FrenchCurve.Backend.Cells.subpixels(:sextant)
      {2, 3}
  """
  @spec subpixels(set) :: {pos_integer, pos_integer}
  def subpixels(set), do: Map.fetch!(@subpixels, set)

  @doc """
  The set a terminal is known to draw well: `:sextant` for iTerm2, `:octant` for
  terminals speaking the kitty graphics protocol (kitty, Ghostty, WezTerm, which draw the
  block glyphs themselves), `:half` for anything else or `nil`.

  Takes a graphics protocol atom, or an environment map as `FrenchCurve.Capability.detect/1`
  reads it, which is the surer guide: a terminal can be driven through a protocol that is
  not its own (iTerm2 through sixel) and still draw the glyphs its name says it does.

      iex> FrenchCurve.Backend.Cells.default_set(:kitty)
      :octant
      iex> FrenchCurve.Backend.Cells.default_set(nil)
      :half
      iex> FrenchCurve.Backend.Cells.default_set(%{"TERM_PROGRAM" => "iTerm.app"})
      :sextant
      iex> FrenchCurve.Backend.Cells.default_set(%{"TERM" => "xterm-ghostty"})
      :octant
  """
  @spec default_set(atom | nil | map) :: set
  def default_set(env) when is_map(env) do
    cond do
      env["TERM_PROGRAM"] == "iTerm.app" or env["LC_TERMINAL"] == "iTerm2" -> :sextant
      Capability.detect(env) == :kitty -> :octant
      true -> :half
    end
  end

  def default_set(:iterm2), do: :sextant
  def default_set(:kitty), do: :octant
  def default_set(_protocol), do: :half

  @doc """
  The glyph of `set` whose lit pixels are `pattern`, a bitmask in row-major order with
  bit 0 the top-left pixel.

      iex> FrenchCurve.Backend.Cells.glyph(:quad, 0b0011)
      "▀"
      iex> FrenchCurve.Backend.Cells.glyph(:sextant, 0b111111)
      "█"
      iex> FrenchCurve.Backend.Cells.glyph(:octant, 0b00000100)
      "𜴀"
      iex> FrenchCurve.Backend.Cells.glyph(:braille, 0b00000001)
      "⠁"
  """
  @spec glyph(set, non_neg_integer) :: binary
  def glyph(:half, 0), do: " "
  def glyph(:half, 1), do: "▀"
  def glyph(:half, 2), do: "▄"
  def glyph(:half, 3), do: "█"
  def glyph(:quad, pattern), do: Enum.at(@quadrants, pattern)
  def glyph(:sextant, pattern), do: Map.fetch!(@sextants, pattern)
  def glyph(:octant, pattern), do: Map.fetch!(@octants, pattern)

  def glyph(:braille, pattern) do
    dots =
      Enum.reduce(0..7, 0, fn index, acc ->
        if (pattern >>> index &&& 1) == 1, do: acc ||| elem(@braille_bits, index), else: acc
      end)

    <<0x2800 + dots::utf8>>
  end

  @doc """
  Returns the cell rows for `raster`.

  ## Options

    * `:set` — the glyph set, default `:half`
    * `:background` — an `{r, g, b}` colour for transparent pixels and for pixels past
      the raster's edge, default `{0, 0, 0}`
    * `:alpha_threshold` — the smallest alpha treated as opaque, default `128`
  """
  @spec render(Raster.t(), keyword) :: [[cell]]
  def render(%Raster{width: width, height: height} = raster, opts \\ []) do
    set = Keyword.get(opts, :set, :half)
    background = Keyword.get(opts, :background, {0, 0, 0})
    threshold = Keyword.get(opts, :alpha_threshold, 128)
    {sx, sy} = subpixels(set)
    cols = div(width + sx - 1, sx)
    rows = div(height + sy - 1, sy)
    rgba = Raster.to_rgba_binary(raster)

    source = %{
      rgba: rgba,
      width: width,
      height: height,
      background: background,
      threshold: threshold
    }

    if available?() and Keyword.get(opts, :native, true) do
      native_rows(rgba, {width, height}, {sx, sy}, background, threshold, set, cols, rows)
    else
      elixir_rows(source, {sx, sy}, set, cols, rows)
    end
  end

  defp elixir_rows(source, {sx, sy}, set, cols, rows) do
    for cy <- 0..(rows - 1)//1 do
      for cx <- 0..(cols - 1)//1 do
        {pattern, fg, bg} = source |> cell_pixels({cx * sx, cy * sy}, {sx, sy}) |> split()
        {glyph(set, pattern), fg, bg}
      end
    end
  end

  defp native_rows(rgba, size, subpixels, background, threshold, set, cols, rows) do
    cells = quantise(rgba, size, subpixels, background, threshold)

    for cy <- 0..(rows - 1)//1 do
      for cx <- 0..(cols - 1)//1 do
        <<pattern, fr, fg, fb, br, bg, bb>> = binary_part(cells, (cy * cols + cx) * 7, 7)
        {glyph(set, pattern), {fr, fg, fb}, {br, bg, bb}}
      end
    end
  end

  @doc false
  def load_nif do
    path = :french_curve |> :code.priv_dir() |> Path.join("cells_nif") |> to_charlist()

    case :erlang.load_nif(path, 0) do
      :ok -> :persistent_term.put({__MODULE__, :native?}, true)
      {:error, _reason} -> :ok
    end

    :ok
  end

  @doc "Whether the quantisation is done by the NIF rather than in Elixir."
  @spec available?() :: boolean()
  def available?, do: :persistent_term.get({__MODULE__, :native?}, false)

  @doc false
  def quantise(_rgba, _size, _subpixels, _background, _threshold),
    do: :erlang.nif_error(:not_loaded)

  defp cell_pixels(source, {left, top}, {sx, sy}) do
    for dy <- 0..(sy - 1)//1, dx <- 0..(sx - 1)//1 do
      pixel(
        source.rgba,
        source.width,
        source.height,
        left + dx,
        top + dy,
        source.background,
        source.threshold
      )
    end
  end

  @doc """
  Flattens cell rows to one newline-separated string with 24-bit colours, every glyph
  wrapped in its foreground and background sequence and a reset after each row.
  """
  @spec to_ansi([[cell]]) :: binary
  def to_ansi(rows) do
    Enum.map_join(rows, "\n", fn row -> Enum.map_join(row, "", &cell_to_ansi/1) <> "\e[0m" end)
  end

  defp cell_to_ansi({glyph, {fr, fg, fb}, {br, bg, bb}}) do
    "\e[38;2;#{fr};#{fg};#{fb}m\e[48;2;#{br};#{bg};#{bb}m" <> glyph
  end

  defp pixel(rgba, width, height, x, y, background, threshold)
       when x < width and y < height do
    case binary_part(rgba, (y * width + x) * 4, 4) do
      <<r, g, b, a>> when a >= threshold -> {r, g, b}
      _clear -> background
    end
  end

  defp pixel(_rgba, _width, _height, _x, _y, background, _threshold), do: background

  defp split(pixels) do
    case Enum.min_max_by(pixels, &luminance/1) do
      {same, same} -> {0, same, same}
      {darkest, brightest} -> split_towards(pixels, darkest, brightest)
    end
  end

  defp split_towards(pixels, darkest, brightest) do
    {bits, lit, unlit} =
      pixels
      |> Enum.with_index()
      |> Enum.reduce({0, [], []}, fn {pixel, index}, {bits, lit, unlit} ->
        if distance(pixel, brightest) < distance(pixel, darkest),
          do: {bits ||| 1 <<< index, [pixel | lit], unlit},
          else: {bits, lit, [pixel | unlit]}
      end)

    {bits, mean(lit), mean(unlit)}
  end

  defp luminance({r, g, b}), do: r * 299 + g * 587 + b * 114

  defp distance({r1, g1, b1}, {r2, g2, b2}) do
    (r1 - r2) * (r1 - r2) + (g1 - g2) * (g1 - g2) + (b1 - b2) * (b1 - b2)
  end

  defp mean(pixels) do
    count = length(pixels)

    {rs, gs, bs} =
      Enum.reduce(pixels, {0, 0, 0}, fn {r, g, b}, {rs, gs, bs} -> {rs + r, gs + g, bs + b} end)

    {div(rs, count), div(gs, count), div(bs, count)}
  end
end
