defmodule FrenchCurve.Raster do
  @moduledoc """
  A fixed-size RGBA pixel buffer, the value every drawing and backend function operates on.

  A raster has a `width`, a `height`, a `background` colour returned for any pixel never
  written, and its contents in two layers:

    * `rgba` — a dense row-major `width * height * 4` byte base buffer, or `nil` when every
      base pixel is the background
    * `pixels` — a sparse map of `{x, y}` to colour written over the base

  `get_pixel/3` reads the top layer first, so the layering is not something a caller has
  to track. `put_pixel/4` and `put_pixels/3` write into `pixels`; `fill_spans/3` writes
  whole horizontal runs straight into the base buffer, which is the fast way to fill
  large areas. `finalize/1` folds the map into the base buffer.

  Coordinates are zero-based with `{0, 0}` at the top left. Writes outside the bounds are
  dropped rather than raising.

      FrenchCurve.Raster.new(4, 2, background: {0, 0, 0, 255})
      |> FrenchCurve.Raster.put_pixel(1, 0, {255, 0, 0, 255})
      |> FrenchCurve.Raster.to_rgba_binary()
  """

  @type channel :: 0..255
  @type color :: {channel, channel, channel, channel}
  @type color_rgb :: {channel, channel, channel}
  @type point :: {non_neg_integer, non_neg_integer}
  @type span :: {integer, integer, integer}
  @type t :: %__MODULE__{
          width: pos_integer,
          height: pos_integer,
          background: color,
          pixels: %{optional(point) => color},
          rgba: binary | nil
        }

  @enforce_keys [:width, :height, :background]
  defstruct [:width, :height, :background, pixels: %{}, rgba: nil]

  @transparent {0, 0, 0, 0}

  @doc """
  Builds an empty raster `width` by `height` pixels.

  Both dimensions must be positive integers; anything else raises `FunctionClauseError`.

  ## Options

    * `:background` — the `t:color/0` `get_pixel/3` returns for unwritten pixels, default
      `{0, 0, 0, 0}` (transparent black)
  """
  @spec new(pos_integer, pos_integer, keyword) :: t
  def new(width, height, opts \\ [])
      when is_integer(width) and width > 0 and is_integer(height) and height > 0 do
    %__MODULE__{
      width: width,
      height: height,
      background: Keyword.get(opts, :background, @transparent)
    }
  end

  @doc """
  Returns the raster's `{width, height}` in pixels.
  """
  @spec dimensions(t) :: {pos_integer, pos_integer}
  def dimensions(%__MODULE__{width: width, height: height}), do: {width, height}

  @doc """
  Returns whether `{x, y}` falls inside the raster.

  True when `x` and `y` are both non-negative and below `width` and `height` respectively.
  """
  @spec in_bounds?(t, integer, integer) :: boolean
  def in_bounds?(%__MODULE__{width: width, height: height}, x, y) do
    x >= 0 and y >= 0 and x < width and y < height
  end

  @doc """
  Returns `raster` with the pixel at `{x, y}` set to `color`.

  `color` is an `{r, g, b, a}` tuple of bytes and replaces whatever was there; there is no
  alpha blending. Coordinates outside the bounds are ignored and the raster is returned
  unchanged.
  """
  @spec put_pixel(t, integer, integer, color) :: t
  def put_pixel(%__MODULE__{} = raster, x, y, color) do
    if in_bounds?(raster, x, y) do
      %{raster | pixels: Map.put(raster.pixels, {x, y}, color)}
    else
      raster
    end
  end

  @doc """
  Returns `raster` with every `{x, y}` in `points` set to `color`.

  Equivalent to `put_pixel/4` for each point, in one map merge. Points outside the bounds
  are ignored.
  """
  @spec put_pixels(t, [{integer, integer}], color) :: t
  def put_pixels(%__MODULE__{} = raster, points, color) do
    inside = Enum.filter(points, fn {x, y} -> in_bounds?(raster, x, y) end)
    %{raster | pixels: Map.merge(raster.pixels, Map.from_keys(inside, color))}
  end

  @doc """
  Returns `raster` with every horizontal span in `spans` filled with `color`.

  Each span is `{y, x_from, x_to}`, both ends inclusive and in either order. Spans are
  clipped to the raster and may overlap. Pending `put_pixel/4` writes are folded into the
  base buffer first, so the spans land on top of everything drawn before them. A `color`
  that is not an `{r, g, b, a}` tuple is written pixel by pixel as `put_pixels/3` does.
  """
  @spec fill_spans(t, [span], color | term) :: t
  def fill_spans(%__MODULE__{} = raster, spans, {r, g, b, a}) do
    runs =
      spans
      |> Enum.flat_map(&clip_span(raster, &1))
      |> Enum.sort()
      |> merge_runs()

    case runs do
      [] ->
        raster

      runs ->
        base = to_rgba_binary(raster)
        %{raster | rgba: splice_fill(base, runs, <<r, g, b, a>>), pixels: %{}}
    end
  end

  def fill_spans(%__MODULE__{} = raster, spans, color) do
    points =
      for {y, x0, x1} <- spans,
          x <- min(x0, x1)..max(x0, x1)//1,
          do: {x, y}

    put_pixels(raster, points, color)
  end

  @doc """
  Returns the `t:color/0` at `{x, y}`.

  Reads a written pixel first, then the base buffer, and falls back to the raster's
  `background`. Out-of-bounds coordinates return the background rather than raising.
  """
  @spec get_pixel(t, integer, integer) :: color
  def get_pixel(%__MODULE__{} = raster, x, y) do
    case Map.get(raster.pixels, {x, y}) do
      nil -> base_pixel(raster, x, y)
      color -> color
    end
  end

  @doc """
  Returns the `{width, height}` rectangle of `raster` whose top left is at `{x, y}`.

  The rectangle must lie inside the raster. The result carries the same background and
  a dense buffer.
  """
  @spec crop(t, point, {pos_integer, pos_integer}) :: t
  def crop(%__MODULE__{} = raster, {x, y}, {width, height})
      when x >= 0 and y >= 0 and width > 0 and height > 0 and x + width <= raster.width and
             y + height <= raster.height do
    source = to_rgba_binary(raster)
    stride = raster.width * 4

    rows =
      for row <- y..(y + height - 1) do
        binary_part(source, row * stride + x * 4, width * 4)
      end

    from_rgba(width, height, IO.iodata_to_binary(rows), background: raster.background)
  end

  @doc """
  Returns every pixel as `height` lists of `width` colours, top row first.

  Each element is a `t:color/0`; unwritten positions come back as the background.
  """
  @spec rows(t) :: [[color]]
  def rows(%__MODULE__{width: width, height: height} = raster) do
    buffer = to_rgba_binary(raster)
    stride = width * 4

    for y <- 0..(height - 1) do
      for <<r, g, b, a <- binary_part(buffer, y * stride, stride)>>, do: {r, g, b, a}
    end
  end

  @doc """
  Returns the raster as a dense row-major RGBA buffer.

  The result is exactly `width * height * 4` bytes, four bytes per pixel in red, green,
  blue, alpha order, rows top to bottom.
  """
  @spec to_rgba_binary(t) :: binary
  def to_rgba_binary(%__MODULE__{pixels: pixels} = raster) when map_size(pixels) == 0,
    do: base_binary(raster)

  def to_rgba_binary(%__MODULE__{width: width, pixels: pixels} = raster) do
    runs =
      pixels
      |> Enum.map(fn {{x, y}, {r, g, b, a}} -> {y * width + x, <<r, g, b, a>>} end)
      |> Enum.sort()

    splice_pixels(base_binary(raster), runs)
  end

  @doc """
  Returns `raster` with its pixel map folded into the dense base buffer.

  Pixel values are unchanged. Call this on a raster that will be sent to a backend more
  than once, so `to_rgba_binary/1` returns the buffer without rebuilding it. Drawing
  after `finalize/1` stays correct.
  """
  @spec finalize(t) :: t
  def finalize(%__MODULE__{rgba: rgba, pixels: pixels} = raster)
      when is_binary(rgba) and map_size(pixels) == 0,
      do: raster

  def finalize(%__MODULE__{} = raster), do: %{raster | rgba: to_rgba_binary(raster), pixels: %{}}

  @doc """
  Builds a raster from an existing dense RGBA buffer.

  `binary` must be exactly `width * height * 4` bytes, four bytes per pixel in red,
  green, blue, alpha order and rows top to bottom; a mismatched size raises
  `FunctionClauseError`. The buffer becomes the raster's base without being copied.

  ## Options

    * `:background` — the `t:color/0` returned for out-of-bounds reads, default
      `{0, 0, 0, 0}`
  """
  @spec from_rgba(pos_integer, pos_integer, binary, keyword) :: t
  def from_rgba(width, height, binary, opts \\ [])
      when is_integer(width) and width > 0 and is_integer(height) and height > 0 and
             is_binary(binary) and byte_size(binary) == width * height * 4 do
    %__MODULE__{
      width: width,
      height: height,
      background: Keyword.get(opts, :background, @transparent),
      rgba: binary
    }
  end

  defp base_pixel(%__MODULE__{rgba: rgba, width: width} = raster, x, y) when is_binary(rgba) do
    if in_bounds?(raster, x, y) do
      <<r, g, b, a>> = binary_part(rgba, (y * width + x) * 4, 4)
      {r, g, b, a}
    else
      raster.background
    end
  end

  defp base_pixel(%__MODULE__{} = raster, _x, _y), do: raster.background

  defp base_binary(%__MODULE__{rgba: rgba}) when is_binary(rgba), do: rgba

  defp base_binary(%__MODULE__{background: {r, g, b, a}, width: width, height: height}),
    do: :binary.copy(<<r, g, b, a>>, width * height)

  defp clip_span(%__MODULE__{width: width, height: height}, {y, x0, x1}) do
    left = max(min(x0, x1), 0)
    right = min(max(x0, x1), width - 1)

    if y >= 0 and y < height and left <= right,
      do: [{y * width + left, y * width + right}],
      else: []
  end

  defp merge_runs([]), do: []

  defp merge_runs([first | rest]),
    do: rest |> Enum.reduce([first], &merge_run/2) |> Enum.reverse()

  defp merge_run({from, to}, [{last_from, last_to} | done]) when from <= last_to + 1,
    do: [{last_from, max(to, last_to)} | done]

  defp merge_run(run, done), do: [run | done]

  defp splice_fill(base, runs, pixel) do
    {parts, position} =
      Enum.reduce(runs, {[], 0}, fn {from, to}, {parts, position} ->
        gap = binary_part(base, position * 4, (from - position) * 4)
        {[:binary.copy(pixel, to - from + 1), gap | parts], to + 1}
      end)

    finish_splice(base, parts, position)
  end

  defp splice_pixels(base, runs) do
    {parts, position} =
      Enum.reduce(runs, {[], 0}, fn {index, pixel}, {parts, position} ->
        gap = binary_part(base, position * 4, (index - position) * 4)
        {[pixel, gap | parts], index + 1}
      end)

    finish_splice(base, parts, position)
  end

  defp finish_splice(base, parts, position) do
    tail = binary_part(base, position * 4, byte_size(base) - position * 4)
    IO.iodata_to_binary(Enum.reverse([tail | parts]))
  end
end
