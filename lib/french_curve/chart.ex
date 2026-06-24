defmodule FrenchCurve.Chart do
  @moduledoc false

  alias FrenchCurve.{Curve, Draw, Raster}

  @default_color {255, 255, 255, 255}
  @default_fill_opacity 0.4

  @spec line([number], keyword) :: Raster.t()
  def line(values, opts \\ [])

  def line([], opts), do: new_raster(opts)

  def line(values, opts) do
    color = Keyword.get(opts, :color, @default_color)

    points = curve_points(values, opts)

    Draw.polyline(new_raster(opts), Curve.to_pixels(points), color)
  end

  @spec area([number], keyword) :: Raster.t()
  def area(values, opts \\ [])

  def area([], opts), do: new_raster(opts)

  def area(values, opts) do
    color = Keyword.get(opts, :color, @default_color)
    fill = scale(color, Keyword.get(opts, :fill_opacity, @default_fill_opacity))
    baseline = Keyword.get(opts, :height, 24) - 1

    points = curve_points(values, opts)

    new_raster(opts)
    |> fill_area(points, baseline, fill)
    |> Draw.polyline(Curve.to_pixels(points), color)
  end

  defp curve_points(values, opts) do
    width = Keyword.get(opts, :width, 80)
    height = Keyword.get(opts, :height, 24)
    {lo, hi} = range(values, opts)

    values
    |> float_points(width, height, lo, hi)
    |> maybe_smooth(Keyword.get(opts, :smooth, false))
  end

  defp new_raster(opts) do
    width = Keyword.get(opts, :width, 80)
    height = Keyword.get(opts, :height, 24)

    case Keyword.get(opts, :background) do
      nil -> Raster.new(width, height)
      background -> Raster.new(width, height, background: background)
    end
  end

  defp range(values, opts) do
    lo = Keyword.get(opts, :min, Enum.min(values))
    hi = Keyword.get(opts, :max, Enum.max(values))
    if hi == lo, do: {lo, lo + 1}, else: {lo, hi}
  end

  defp float_points(values, width, height, lo, hi) do
    count = length(values)

    values
    |> Enum.with_index()
    |> Enum.map(fn {value, index} ->
      {x_for(index, count, width), y_for(value, lo, hi, height)}
    end)
  end

  defp x_for(_index, 1, _width), do: 0.0
  defp x_for(index, count, width), do: index * (width - 1) / (count - 1)

  defp y_for(value, lo, hi, height), do: (hi - value) / (hi - lo) * (height - 1)

  defp maybe_smooth(points, false), do: points
  defp maybe_smooth(points, true), do: Curve.catmull_rom(points)

  defp fill_area(raster, points, baseline, color) do
    points
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.reduce(raster, fn [a, b], acc -> fill_span(acc, a, b, baseline, color) end)
  end

  defp fill_span(raster, {x1, y1}, {x2, y2}, baseline, color) do
    {xa, ya, xb, yb} = order(x1, y1, x2, y2)

    Enum.reduce(round(xa)..round(xb), raster, fn column, acc ->
      top = round(interpolate(xa, ya, xb, yb, column))
      Draw.line(acc, {column, top}, {column, baseline}, color)
    end)
  end

  defp order(x1, y1, x2, y2) when x1 <= x2, do: {x1, y1, x2, y2}
  defp order(x1, y1, x2, y2), do: {x2, y2, x1, y1}

  defp interpolate(xa, ya, xa, _yb, _column), do: ya
  defp interpolate(xa, ya, xb, yb, column), do: ya + (yb - ya) * (column - xa) / (xb - xa)

  defp scale({r, g, b, a}, opacity) do
    {round(r * opacity), round(g * opacity), round(b * opacity), a}
  end
end
