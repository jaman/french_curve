defmodule FrenchCurve.Raster do
  @moduledoc """
  A fixed-size RGBA pixel buffer, the value every drawing and backend function operates on.

  A raster has a `width`, a `height`, a `background` colour returned for any pixel never
  written, and two interchangeable representations of its contents:

    * `pixels` — a sparse map of `{x, y}` to colour, cheap to draw into
    * `rgba` — a dense row-major `width * height * 4` byte buffer, what the backends send

  `get_pixel/3` reads from whichever is populated, so the representation is not something
  a caller has to track. `finalize/1` caches the dense buffer on a raster that is about to
  be sent repeatedly; drawing into a finalized raster discards the cache.

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
  unchanged. A raster holding a cached dense buffer loses that cache here.
  """
  @spec put_pixel(t, integer, integer, color) :: t
  def put_pixel(%__MODULE__{} = raster, x, y, color) do
    if in_bounds?(raster, x, y) do
      raster |> materialize() |> put_color(x, y, color)
    else
      raster
    end
  end

  defp put_color(raster, x, y, color) do
    %{raster | pixels: Map.put(raster.pixels, {x, y}, color)}
  end

  defp materialize(%__MODULE__{rgba: nil} = raster), do: raster

  defp materialize(%__MODULE__{rgba: rgba, pixels: pixels, width: width} = raster)
       when map_size(pixels) == 0 do
    %{raster | pixels: build_pixels(rgba, width), rgba: nil}
  end

  defp materialize(%__MODULE__{} = raster), do: %{raster | rgba: nil}

  @doc """
  Returns the `t:color/0` at `{x, y}`.

  Reads a written pixel first, then the cached dense buffer, and falls back to the
  raster's `background`. Out-of-bounds coordinates return the background rather than
  raising.
  """
  @spec get_pixel(t, integer, integer) :: color
  def get_pixel(%__MODULE__{} = raster, x, y) do
    case Map.get(raster.pixels, {x, y}) do
      nil -> cached_pixel(raster, x, y)
      color -> color
    end
  end

  defp cached_pixel(%__MODULE__{rgba: rgba, width: width} = raster, x, y) when is_binary(rgba) do
    if in_bounds?(raster, x, y) do
      <<r, g, b, a>> = binary_part(rgba, (y * width + x) * 4, 4)
      {r, g, b, a}
    else
      raster.background
    end
  end

  defp cached_pixel(%__MODULE__{} = raster, _x, _y), do: raster.background

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
    for y <- 0..(height - 1) do
      for x <- 0..(width - 1) do
        get_pixel(raster, x, y)
      end
    end
  end

  @doc """
  Returns the raster as a dense row-major RGBA buffer.

  The result is exactly `width * height * 4` bytes, four bytes per pixel in red, green,
  blue, alpha order, rows top to bottom. Returns the cached buffer when one is present.
  """
  @spec to_rgba_binary(t) :: binary
  def to_rgba_binary(%__MODULE__{rgba: rgba}) when is_binary(rgba), do: rgba

  def to_rgba_binary(%__MODULE__{pixels: pixels, background: {r, g, b, a}} = raster)
      when map_size(pixels) == 0,
      do: :binary.copy(<<r, g, b, a>>, raster.width * raster.height)

  def to_rgba_binary(%__MODULE__{} = raster) do
    for row <- rows(raster), {r, g, b, a} <- row, into: <<>>, do: <<r, g, b, a>>
  end

  @doc """
  Returns `raster` with its dense RGBA buffer computed and cached in the `rgba` field.

  Pixel values are unchanged. Call this on a raster that will be sent to a backend more
  than once; a raster that already carries a cache is returned as is. `put_pixel/4` after
  `finalize/1` drops the cache, so finalize last.
  """
  @spec finalize(t) :: t
  def finalize(%__MODULE__{rgba: rgba} = raster) when is_binary(rgba), do: raster
  def finalize(%__MODULE__{} = raster), do: %{raster | rgba: to_rgba_binary(raster)}

  @doc """
  Builds a raster from an existing dense RGBA buffer.

  `binary` must be exactly `width * height * 4` bytes, four bytes per pixel in red,
  green, blue, alpha order and rows top to bottom; a mismatched size raises
  `FunctionClauseError`. The buffer is kept as the raster's cache rather than expanded,
  so this is the cheap way to load pixels produced elsewhere.

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

  defp build_pixels(binary, width) do
    colors = for <<r, g, b, a <- binary>>, do: {r, g, b, a}

    colors
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {color, index}, acc ->
      if color == @transparent do
        acc
      else
        Map.put(acc, {rem(index, width), div(index, width)}, color)
      end
    end)
  end
end
