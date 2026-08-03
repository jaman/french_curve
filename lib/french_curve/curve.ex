defmodule FrenchCurve.Curve do
  @moduledoc """
  Smooths a path of control points into a dense curve and rounds points to pixels.

  Works in floating-point coordinate space, ahead of rasterisation: feed the result to
  `FrenchCurve.Draw.polyline/3` through `to_pixels/1`.

      [{0, 10}, {10, 2}, {20, 14}, {30, 6}]
      |> FrenchCurve.Curve.catmull_rom()
      |> FrenchCurve.Curve.to_pixels()
  """

  @type point :: {number, number}

  @default_samples 16

  @doc """
  Returns a Catmull-Rom spline passing through every point of `points`, in order.

  The curve is interpolating, so each input point appears in the output. The first and
  last points are duplicated to give the end segments the neighbour they need, which makes
  the curve start and end exactly on them. Fewer than two points are returned unchanged.

  The output has `samples * (length(points) - 1) + 1` points.

  ## Options

    * `:samples` — points generated per input segment, default `16`. Higher is smoother
      and more expensive.
  """
  @spec catmull_rom([point], keyword) :: [point]
  def catmull_rom(points, opts \\ [])

  def catmull_rom(points, _opts) when length(points) < 2, do: points

  def catmull_rom(points, opts) do
    samples = Keyword.get(opts, :samples, @default_samples)

    points
    |> pad_endpoints()
    |> Enum.chunk_every(4, 1, :discard)
    |> Enum.flat_map(fn [p0, p1, p2, p3] -> segment(p0, p1, p2, p3, samples) end)
    |> Kernel.++([List.last(points)])
  end

  @doc """
  Rounds each coordinate to the nearest integer, giving points `FrenchCurve.Draw` accepts.

  Consecutive points that round to the same pixel are kept as duplicates.
  """
  @spec to_pixels([point]) :: [{integer, integer}]
  def to_pixels(points) do
    Enum.map(points, fn {x, y} -> {round(x), round(y)} end)
  end

  defp pad_endpoints([first | _] = points) do
    [first] ++ points ++ [List.last(points)]
  end

  defp segment(p0, p1, p2, p3, samples) do
    for i <- 0..(samples - 1) do
      catmull_point(p0, p1, p2, p3, i / samples)
    end
  end

  defp catmull_point({x0, y0}, {x1, y1}, {x2, y2}, {x3, y3}, t) do
    {catmull_axis(x0, x1, x2, x3, t), catmull_axis(y0, y1, y2, y3, t)}
  end

  defp catmull_axis(a0, a1, a2, a3, t) do
    t2 = t * t
    t3 = t2 * t

    0.5 *
      (2 * a1 + (-a0 + a2) * t + (2 * a0 - 5 * a1 + 4 * a2 - a3) * t2 +
         (-a0 + 3 * a1 - 3 * a2 + a3) * t3)
  end
end
