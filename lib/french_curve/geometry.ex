defmodule FrenchCurve.Geometry do
  @moduledoc false

  @type region :: {pos_integer, pos_integer}
  @type cell_px :: {pos_integer, pos_integer}

  @default_cell_px {10, 20}
  @braille_cell_px {2, 4}
  @cell_size_query "\e[16t"
  @cell_size_reply ~r/\e\[6;(\d+);(\d+)t/

  @spec cell_size_query() :: binary
  def cell_size_query, do: @cell_size_query

  @spec parse_cell_size(binary) :: {:ok, cell_px} | :error
  def parse_cell_size(reply) when is_binary(reply) do
    case Regex.run(@cell_size_reply, reply) do
      [_match, height, width] -> {:ok, {String.to_integer(width), String.to_integer(height)}}
      _ -> :error
    end
  end

  @spec detect_cell_size((binary -> binary | nil)) :: {:ok, cell_px} | :error
  def detect_cell_size(query_io) when is_function(query_io, 1) do
    case query_io.(@cell_size_query) do
      reply when is_binary(reply) -> parse_cell_size(reply)
      _ -> :error
    end
  end

  @spec default_cell_px() :: cell_px
  def default_cell_px, do: @default_cell_px

  @spec braille_cell_px() :: cell_px
  def braille_cell_px, do: @braille_cell_px

  @spec pixels_for_cells(region, cell_px | :unknown) :: {pos_integer, pos_integer}
  def pixels_for_cells(region, :unknown), do: pixels_for_cells(region, @default_cell_px)

  def pixels_for_cells({cols, rows}, {cell_width, cell_height}) do
    {cols * cell_width, rows * cell_height}
  end
end
