defmodule FrenchCurve.Raster do
  @moduledoc false

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

  @spec new(pos_integer, pos_integer, keyword) :: t
  def new(width, height, opts \\ [])
      when is_integer(width) and width > 0 and is_integer(height) and height > 0 do
    %__MODULE__{
      width: width,
      height: height,
      background: Keyword.get(opts, :background, @transparent)
    }
  end

  @spec dimensions(t) :: {pos_integer, pos_integer}
  def dimensions(%__MODULE__{width: width, height: height}), do: {width, height}

  @spec in_bounds?(t, integer, integer) :: boolean
  def in_bounds?(%__MODULE__{width: width, height: height}, x, y) do
    x >= 0 and y >= 0 and x < width and y < height
  end

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

  @spec rows(t) :: [[color]]
  def rows(%__MODULE__{width: width, height: height} = raster) do
    for y <- 0..(height - 1) do
      for x <- 0..(width - 1) do
        get_pixel(raster, x, y)
      end
    end
  end

  @spec to_rgba_binary(t) :: binary
  def to_rgba_binary(%__MODULE__{rgba: rgba}) when is_binary(rgba), do: rgba

  def to_rgba_binary(%__MODULE__{} = raster) do
    for row <- rows(raster), {r, g, b, a} <- row, into: <<>>, do: <<r, g, b, a>>
  end

  @spec finalize(t) :: t
  def finalize(%__MODULE__{rgba: rgba} = raster) when is_binary(rgba), do: raster
  def finalize(%__MODULE__{} = raster), do: %{raster | rgba: to_rgba_binary(raster)}

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
