defmodule FrenchCurve.Draw do
  @moduledoc """
  Rasterises lines, rectangles and circles into a `FrenchCurve.Raster`.

  Every function takes a raster as its first argument and returns a new one, so calls
  compose in a pipeline. Coordinates are integer pixels, `{0, 0}` at the top left, and may
  fall outside the raster: the parts that land inside are drawn and the rest is clipped.
  Colours are `{r, g, b, a}` byte tuples written opaquely, with no blending against what
  is already there.

      FrenchCurve.Raster.new(40, 20)
      |> FrenchCurve.Draw.rect({0, 0}, {39, 19}, {80, 80, 80, 255})
      |> FrenchCurve.Draw.fill_circle({20, 10}, 6, {255, 0, 0, 255})
  """

  alias FrenchCurve.Raster

  @type coord :: {integer, integer}

  @doc """
  Draws a one-pixel-wide line between the two endpoints, both inclusive.

  Handles any direction, including purely horizontal, vertical and single-point lines.
  """
  @spec line(Raster.t(), coord, coord, Raster.color()) :: Raster.t()
  def line(%Raster{} = raster, {x0, y0}, {x1, y1}, color) do
    plot_line(raster, x0, y0, x1, y1, color)
  end

  @doc """
  Draws a connected run of line segments through `points` in order.

  A single point plots that pixel and an empty list leaves the raster unchanged. Points
  are not closed back to the first one; pass the first point again to close the shape.
  """
  @spec polyline(Raster.t(), [coord], Raster.color()) :: Raster.t()
  def polyline(%Raster{} = raster, [point], color) do
    {x, y} = point
    Raster.put_pixel(raster, x, y, color)
  end

  def polyline(%Raster{} = raster, [from | [to | _] = rest], color) do
    raster
    |> line(from, to, color)
    |> polyline(rest, color)
  end

  def polyline(%Raster{} = raster, [], _color), do: raster

  @doc """
  Draws the four edges of the rectangle spanned by two opposite corners.

  Both corners are inclusive and may be given in any order. The interior is untouched.
  """
  @spec rect(Raster.t(), coord, coord, Raster.color()) :: Raster.t()
  def rect(%Raster{} = raster, {x0, y0}, {x1, y1}, color) do
    {left, right} = min_max(x0, x1)
    {top, bottom} = min_max(y0, y1)

    raster
    |> line({left, top}, {right, top}, color)
    |> line({left, bottom}, {right, bottom}, color)
    |> line({left, top}, {left, bottom}, color)
    |> line({right, top}, {right, bottom}, color)
  end

  @doc """
  Fills every pixel of the rectangle spanned by two opposite corners, edges included.

  Both corners are inclusive and may be given in any order.
  """
  @spec fill_rect(Raster.t(), coord, coord, Raster.color()) :: Raster.t()
  def fill_rect(%Raster{} = raster, {x0, y0}, {x1, y1}, color) do
    {left, right} = min_max(x0, x1)
    {top, bottom} = min_max(y0, y1)

    for x <- left..right, y <- top..bottom, reduce: raster do
      acc -> Raster.put_pixel(acc, x, y, color)
    end
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

    filled =
      Enum.reduce(floor(top)..ceil(bottom)//1, raster, fn y, acc ->
        centre = y + 0.5

        edges
        |> Enum.flat_map(&crossing(&1, centre))
        |> Enum.sort()
        |> Enum.chunk_every(2, 2, :discard)
        |> Enum.reduce(acc, fn [from, to], row ->
          line(row, {round(from), y}, {round(to - 0.0001), y}, color)
        end)
      end)

    polyline(filled, Enum.map(points ++ [hd(points)], &round_point/1), color)
  end

  defp crossing({{x0, y0}, {x1, y1}}, y) do
    if (y0 <= y and y < y1) or (y1 <= y and y < y0) do
      [x0 + (y - y0) * (x1 - x0) / (y1 - y0)]
    else
      []
    end
  end

  defp round_point({x, y}), do: {round(x), round(y)}

  @doc """
  Draws a one-pixel-wide circle outline of `radius` pixels around the centre `{cx, cy}`.

  `radius` must be a non-negative integer. The interior is untouched.
  """
  @spec circle(Raster.t(), coord, non_neg_integer, Raster.color()) :: Raster.t()
  def circle(%Raster{} = raster, {cx, cy}, radius, color) do
    plot_circle(raster, cx, cy, radius, 0, radius, 1 - radius, color)
  end

  @doc """
  Fills a disc of `radius` pixels around the centre `{cx, cy}`.

  `radius` must be a non-negative integer.
  """
  @spec fill_circle(Raster.t(), coord, non_neg_integer, Raster.color()) :: Raster.t()
  def fill_circle(%Raster{} = raster, {cx, cy}, radius, color) do
    Enum.reduce(-radius..radius//1, raster, fn dy, acc ->
      half = round(:math.sqrt(max(0, radius * radius - dy * dy)))
      line(acc, {cx - half, cy + dy}, {cx + half, cy + dy}, color)
    end)
  end

  defp plot_circle(raster, _cx, _cy, _radius, x, y, _err, _color) when x > y, do: raster

  defp plot_circle(raster, cx, cy, radius, x, y, err, color) do
    raster
    |> octants(cx, cy, x, y, color)
    |> plot_circle_next(cx, cy, radius, x, y, err, color)
  end

  defp plot_circle_next(raster, cx, cy, radius, x, y, err, color) when err < 0 do
    plot_circle(raster, cx, cy, radius, x + 1, y, err + 2 * (x + 1) + 1, color)
  end

  defp plot_circle_next(raster, cx, cy, radius, x, y, err, color) do
    plot_circle(raster, cx, cy, radius, x + 1, y - 1, err + 2 * (x + 1) - 2 * (y - 1) + 1, color)
  end

  defp octants(raster, cx, cy, x, y, color) do
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
    |> Enum.reduce(raster, fn {px, py}, acc -> Raster.put_pixel(acc, px, py, color) end)
  end

  defp plot_line(raster, x0, y0, x1, y1, color) do
    deltas = {abs(x1 - x0), -abs(y1 - y0)}
    steps = {step(x0, x1), step(y0, y1)}
    {dx, dy} = deltas
    walk(raster, {x0, y0}, {x1, y1}, deltas, steps, dx + dy, color)
  end

  defp walk(raster, {x, y}, {x, y}, _deltas, _steps, _err, color) do
    Raster.put_pixel(raster, x, y, color)
  end

  defp walk(raster, {x, y}, target, {dx, dy} = deltas, {sx, sy} = steps, err, color) do
    raster = Raster.put_pixel(raster, x, y, color)
    e2 = 2 * err
    {x, err} = advance(x, sx, err, dy, e2 >= dy)
    {y, err} = advance(y, sy, err, dx, e2 <= dx)
    walk(raster, {x, y}, target, deltas, steps, err, color)
  end

  defp advance(value, step, err, delta, true), do: {value + step, err + delta}
  defp advance(value, _step, err, _delta, false), do: {value, err}

  defp step(a, b) when a < b, do: 1
  defp step(_a, _b), do: -1

  defp min_max(a, b) when a <= b, do: {a, b}
  defp min_max(a, b), do: {b, a}
end
