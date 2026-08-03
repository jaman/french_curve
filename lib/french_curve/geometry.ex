defmodule FrenchCurve.Geometry do
  @moduledoc """
  Converts between terminal cells and pixels.

  Sizing a raster to a region of the screen needs the terminal's cell size in pixels,
  which only the terminal knows. `cell_size_query/0` returns the escape sequence that asks
  for it and `parse_cell_size/1` reads the answer; `detect_cell_size/1` does both through a
  callback you supply. When the terminal will not say, `default_cell_px/0` stands in.

  Sizes are `{width, height}` in pixels throughout, and regions are `{cols, rows}` in
  cells.

      cell_px =
        case FrenchCurve.Geometry.detect_cell_size(&query_terminal/1) do
          {:ok, size} -> size
          :error -> FrenchCurve.Geometry.default_cell_px()
        end

      {width, height} = FrenchCurve.Geometry.pixels_for_cells({40, 12}, cell_px)
  """

  @type region :: {pos_integer, pos_integer}
  @type cell_px :: {pos_integer, pos_integer}

  @default_cell_px {10, 20}
  @braille_cell_px {2, 4}
  @cell_size_query "\e[16t"
  @cell_size_reply ~r/\e\[6;(\d+);(\d+)t/

  @doc """
  Returns the escape sequence that asks the terminal for its cell size in pixels.

  Write it to the terminal and read the reply back with `parse_cell_size/1`.
  """
  @spec cell_size_query() :: binary
  def cell_size_query, do: @cell_size_query

  @doc """
  Parses a terminal's reply to `cell_size_query/0`.

  Expects a binary containing `\\e[6;<height>;<width>t`; surrounding bytes are ignored.
  Returns `{:ok, {width, height}}` in pixels, or `:error` if the reply does not match.
  Note that the terminal reports height before width and this returns width first.
  """
  @spec parse_cell_size(binary) :: {:ok, cell_px} | :error
  def parse_cell_size(reply) when is_binary(reply) do
    case Regex.run(@cell_size_reply, reply) do
      [_match, height, width] -> {:ok, {String.to_integer(width), String.to_integer(height)}}
      _ -> :error
    end
  end

  @doc """
  Asks the terminal for its cell size through `query_io` and parses the reply.

  `query_io` is a one-argument function; it is called with `cell_size_query/0` and must
  write that to the terminal and return the terminal's raw reply as a binary, or any
  non-binary if there was none. Returns `{:ok, {width, height}}` in pixels, or `:error`
  when no reply came back or it could not be parsed.
  """
  @spec detect_cell_size((binary -> binary | nil)) :: {:ok, cell_px} | :error
  def detect_cell_size(query_io) when is_function(query_io, 1) do
    case query_io.(@cell_size_query) do
      reply when is_binary(reply) -> parse_cell_size(reply)
      _ -> :error
    end
  end

  @doc """
  Returns the assumed cell size, `{10, 20}` pixels, for terminals that do not report one.
  """
  @spec default_cell_px() :: cell_px
  def default_cell_px, do: @default_cell_px

  @doc """
  Returns the pixels one braille cell covers, `{2, 4}`.

  Fixed by the braille dot layout, not by the terminal: `FrenchCurve.Backend.Braille` maps
  a 2-by-4 block of raster pixels onto the eight dots of one character.
  """
  @spec braille_cell_px() :: cell_px
  def braille_cell_px, do: @braille_cell_px

  @doc """
  Returns the pixel size `{width, height}` of a `{cols, rows}` region of cells.

  Multiplies each dimension by the corresponding cell dimension. Pass `:unknown` as the
  cell size to use `default_cell_px/0`.
  """
  @spec pixels_for_cells(region, cell_px | :unknown) :: {pos_integer, pos_integer}
  def pixels_for_cells(region, :unknown), do: pixels_for_cells(region, @default_cell_px)

  def pixels_for_cells({cols, rows}, {cell_width, cell_height}) do
    {cols * cell_width, rows * cell_height}
  end
end
