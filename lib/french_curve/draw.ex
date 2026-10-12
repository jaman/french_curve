defmodule FrenchCurve.Draw do
  @moduledoc """
  Rasterises lines, rectangles and circles into a `FrenchCurve.Raster`.

  Every function takes a raster as its first argument and returns a new one, so calls
  compose in a pipeline. Coordinates are integer pixels, `{0, 0}` at the top left, and may
  fall outside the raster: the parts that land inside are drawn and the rest is clipped.
  Colours are `{r, g, b, a}` byte tuples written opaquely, with no blending against what
  is already there.

  Outlines are written as one batch of pixels and filled shapes as one batch of
  horizontal spans, so a call costs one raster update however many pixels it covers.

      FrenchCurve.Raster.new(40, 20)
      |> FrenchCurve.Draw.rect({0, 0}, {39, 19}, {80, 80, 80, 255})
      |> FrenchCurve.Draw.fill_circle({20, 10}, 6, {255, 0, 0, 255})
  """

  alias FrenchCurve.Raster

  @type coord :: {integer, integer}
  @type column :: {integer, integer, integer}

  @doc """
  Draws a one-pixel-wide line between the two endpoints, both inclusive.

  Handles any direction, including purely horizontal, vertical and single-point lines.
  """
  @spec line(Raster.t(), coord, coord, Raster.color()) :: Raster.t()
  def line(%Raster{} = raster, from, to, color) do
    Raster.put_pixels(raster, line_points(from, to), color)
  end

  @doc """
  Draws a connected run of line segments through `points` in order.

  A single point plots that pixel and an empty list leaves the raster unchanged. Points
  are not closed back to the first one; pass the first point again to close the shape.
  """
  @spec polyline(Raster.t(), [coord], Raster.color()) :: Raster.t()
  def polyline(%Raster{} = raster, points, color) do
    Raster.put_pixels(raster, polyline_points(points), color)
  end

  @doc """
  Draws the four edges of the rectangle spanned by two opposite corners.

  Both corners are inclusive and may be given in any order. The interior is untouched.
  """
  @spec rect(Raster.t(), coord, coord, Raster.color()) :: Raster.t()
  def rect(%Raster{} = raster, {x0, y0}, {x1, y1}, color) do
    {left, right} = min_max(x0, x1)
    {top, bottom} = min_max(y0, y1)

    polyline(
      raster,
      [{left, top}, {right, top}, {right, bottom}, {left, bottom}, {left, top}],
      color
    )
  end

  @doc """
  Fills every pixel of the rectangle spanned by two opposite corners, edges included.

  Both corners are inclusive and may be given in any order.
  """
  @spec fill_rect(Raster.t(), coord, coord, Raster.color()) :: Raster.t()
  def fill_rect(%Raster{} = raster, {x0, y0}, {x1, y1}, color) do
    {left, right} = min_max(x0, x1)
    {top, bottom} = min_max(y0, y1)
    Raster.fill_spans(raster, for(y <- top..bottom, do: {y, left, right}), color)
  end

  @doc """
  Fills vertical columns, each `{x, y_from, y_to}` with both ends inclusive and in either
  order.

  Columns may repeat an `x` or overlap; the union is filled. The columns are written as
  horizontal spans in one raster update.
  """
  @spec fill_columns(Raster.t(), [column], Raster.color()) :: Raster.t()
  def fill_columns(%Raster{} = raster, [], _color), do: raster

  def fill_columns(%Raster{} = raster, columns, color) do
    Raster.fill_spans(raster, columns_to_spans(columns), color)
  end

  @doc """
  Fills the polygon whose corners are `points`, edges included.

  The polygon is closed from the last point back to the first. Points may be fractional;
  a pixel is filled when its centre lies inside, using the even-odd rule, and the outline
  is drawn as well so thin shapes are never lost. Fewer than three points draw as a
  polyline.
  """
  @spec fill_polygon(Raster.t(), [{number, number}], Raster.color()) :: Raster.t()
  def fill_polygon(%Raster{} = raster, points, color) when length(points) < 3 do
    polyline(raster, Enum.map(points, &round_point/1), color)
  end

  def fill_polygon(%Raster{} = raster, points, color) do
    edges = Enum.zip(points, tl(points) ++ [hd(points)])
    {top, bottom} = points |> Enum.map(&elem(&1, 1)) |> Enum.min_max()

    spans =
      for y <- floor(top)..ceil(bottom)//1,
          [from, to] <- row_crossings(edges, y + 0.5) do
        {y, round(from), round(to - 0.0001)}
      end

    raster
    |> Raster.fill_spans(spans, color)
    |> polyline(Enum.map(points ++ [hd(points)], &round_point/1), color)
  end

  @doc """
  Draws a one-pixel-wide circle outline of `radius` pixels around the centre `{cx, cy}`.

  `radius` must be a non-negative integer. The interior is untouched.
  """
  @spec circle(Raster.t(), coord, non_neg_integer, Raster.color()) :: Raster.t()
  def circle(%Raster{} = raster, {cx, cy}, radius, color) do
    Raster.put_pixels(raster, circle_points(cx, cy, 0, radius, 1 - radius, []), color)
  end

  @doc """
  Fills a disc of `radius` pixels around the centre `{cx, cy}`.

  `radius` must be a non-negative integer.
  """
  @spec fill_circle(Raster.t(), coord, non_neg_integer, Raster.color()) :: Raster.t()
  def fill_circle(%Raster{} = raster, {cx, cy}, radius, color) do
    spans =
      for dy <- -radius..radius//1 do
        half = round(:math.sqrt(max(0, radius * radius - dy * dy)))
        {cy + dy, cx - half, cx + half}
      end

    Raster.fill_spans(raster, spans, color)
  end

  @doc """
  Returns the pixels of the one-pixel-wide line between two endpoints, both inclusive,
  in walking order from `from` to `to`.
  """
  @spec line_points(coord, coord) :: [coord]
  def line_points({x0, y0}, {x1, y1}) do
    deltas = {abs(x1 - x0), -abs(y1 - y0)}
    steps = {step(x0, x1), step(y0, y1)}
    {dx, dy} = deltas
    walk({x0, y0}, {x1, y1}, deltas, steps, dx + dy, [])
  end

  defp polyline_points([]), do: []
  defp polyline_points([point]), do: [point]

  defp polyline_points(points) do
    points
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.flat_map(fn [from, to] -> line_points(from, to) end)
  end

  defp row_crossings(edges, centre) do
    edges
    |> Enum.flat_map(&crossing(&1, centre))
    |> Enum.sort()
    |> Enum.chunk_every(2, 2, :discard)
  end

  defp crossing({{x0, y0}, {x1, y1}}, y) do
    if (y0 <= y and y < y1) or (y1 <= y and y < y0) do
      [x0 + (y - y0) * (x1 - x0) / (y1 - y0)]
    else
      []
    end
  end

  defp columns_to_spans(columns) do
    covered =
      Enum.reduce(columns, %{}, fn {x, y0, y1}, acc ->
        {top, bottom} = min_max(y0, y1)
        Map.update(acc, x, {top, bottom}, fn {t, b} -> {min(t, top), max(b, bottom)} end)
      end)

    xs = covered |> Map.keys() |> Enum.sort()

    {top, bottom} =
      covered |> Map.values() |> Enum.reduce(fn {t, b}, {lo, hi} -> {min(t, lo), max(b, hi)} end)

    for y <- top..bottom//1,
        run <- row_runs(xs, covered, y) do
      run
    end
  end

  defp row_runs(xs, covered, y) do
    xs
    |> Enum.filter(fn x -> covers?(Map.fetch!(covered, x), y) end)
    |> Enum.chunk_while(nil, &extend_run(&1, &2, y), &close_run/1)
  end

  defp covers?({top, bottom}, y), do: top <= y and y <= bottom

  defp extend_run(x, nil, y), do: {:cont, {y, x, x}}
  defp extend_run(x, {y, from, to}, y) when x == to + 1, do: {:cont, {y, from, x}}
  defp extend_run(x, run, y), do: {:cont, run, {y, x, x}}

  defp close_run(nil), do: {:cont, nil}
  defp close_run(run), do: {:cont, run, nil}

  defp round_point({x, y}), do: {round(x), round(y)}

  defp circle_points(_cx, _cy, x, y, _err, acc) when x > y, do: acc

  defp circle_points(cx, cy, x, y, err, acc) do
    acc = octants(cx, cy, x, y) ++ acc

    if err < 0 do
      circle_points(cx, cy, x + 1, y, err + 2 * (x + 1) + 1, acc)
    else
      circle_points(cx, cy, x + 1, y - 1, err + 2 * (x + 1) - 2 * (y - 1) + 1, acc)
    end
  end

  defp octants(cx, cy, x, y) do
    [
      {cx + x, cy + y},
      {cx - x, cy + y},
      {cx + x, cy - y},
      {cx - x, cy - y},
      {cx + y, cy + x},
      {cx - y, cy + x},
      {cx + y, cy - x},
      {cx - y, cy - x}
    ]
  end

  defp walk({x, y}, {x, y}, _deltas, _steps, _err, acc), do: Enum.reverse([{x, y} | acc])

  defp walk({x, y}, target, {dx, dy} = deltas, {sx, sy} = steps, err, acc) do
    e2 = 2 * err
    {next_x, err} = advance(x, sx, err, dy, e2 >= dy)
    {next_y, err} = advance(y, sy, err, dx, e2 <= dx)
    walk({next_x, next_y}, target, deltas, steps, err, [{x, y} | acc])
  end

  defp advance(value, step, err, delta, true), do: {value + step, err + delta}
  defp advance(value, _step, err, _delta, false), do: {value, err}

  defp step(a, b) when a < b, do: 1
  defp step(_a, _b), do: -1

  defp min_max(a, b) when a <= b, do: {a, b}
  defp min_max(a, b), do: {b, a}
end
