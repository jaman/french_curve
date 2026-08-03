defmodule FrenchCurve.Chart do
  @moduledoc """
  Plots a series of numbers as a line or filled-area chart on a `FrenchCurve.Raster`.

  Both functions take a flat list of values and lay them out evenly across the raster's
  width, scaling them to its height. There are no axes, labels or gridlines: the result is
  the plotted series and nothing else, ready to hand to `FrenchCurve.render/3`.

  Values map to pixels so that the first sits at `x = 0` and the last at `x = width - 1`,
  and the data minimum sits at the bottom row with the maximum at the top. A series whose
  values are all equal is drawn along the bottom.

      [3, 1, 4, 1, 5, 9, 2, 6]
      |> FrenchCurve.Chart.area(width: 120, height: 40, smooth: true)
      |> FrenchCurve.to_terminal(:kitty)
  """

  alias FrenchCurve.{Curve, Draw, Raster}

  @default_color {255, 255, 255, 255}
  @default_fill_opacity 0.4

  @doc """
  Plots `values` as a polyline.

  An empty list returns a blank raster of the requested size.

  ## Options

    * `:width` — raster width in pixels, default `80`
    * `:height` — raster height in pixels, default `24`
    * `:color` — the line's `t:FrenchCurve.Raster.color/0`, default `{255, 255, 255, 255}`
    * `:background` — raster background colour, default transparent
    * `:min` — value pinned to the bottom row, default the smallest of `values`
    * `:max` — value pinned to the top row, default the largest of `values`
    * `:smooth` — interpolate a Catmull-Rom spline through the points, default `false`

  Values outside `:min`/`:max` are plotted off the raster and clipped away.
  """
  @spec line([number], keyword) :: Raster.t()
  def line(values, opts \\ [])

  def line([], opts), do: new_raster(opts)

  def line(values, opts) do
    color = Keyword.get(opts, :color, @default_color)

    points = curve_points(values, opts)

    Draw.polyline(new_raster(opts), Curve.to_pixels(points), color)
  end

  @doc """
  Plots `values` as a polyline with the space beneath it filled down to the bottom row.

  An empty list returns a blank raster of the requested size.

  Takes every option of `line/2`, plus:

    * `:fill_opacity` — factor applied to the red, green and blue channels of `:color` to
      get the fill colour, default `0.4`. The alpha channel is copied unchanged, so the
      fill is a darkened `:color` at the same opacity rather than a translucent one.
  """
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
