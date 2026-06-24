defmodule FrenchCurve.Draw do
  @moduledoc false

  alias FrenchCurve.Raster

  @type coord :: {integer, integer}

  @spec line(Raster.t(), coord, coord, Raster.color()) :: Raster.t()
  def line(%Raster{} = raster, {x0, y0}, {x1, y1}, color) do
    plot_line(raster, x0, y0, x1, y1, color)
  end

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

  @spec fill_rect(Raster.t(), coord, coord, Raster.color()) :: Raster.t()
  def fill_rect(%Raster{} = raster, {x0, y0}, {x1, y1}, color) do
    {left, right} = min_max(x0, x1)
    {top, bottom} = min_max(y0, y1)

    for x <- left..right, y <- top..bottom, reduce: raster do
      acc -> Raster.put_pixel(acc, x, y, color)
    end
  end

  @spec circle(Raster.t(), coord, non_neg_integer, Raster.color()) :: Raster.t()
  def circle(%Raster{} = raster, {cx, cy}, radius, color) do
    plot_circle(raster, cx, cy, radius, 0, radius, 1 - radius, color)
  end

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
