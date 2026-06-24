defmodule RenderDemo do
  alias FrenchCurve.{Capability, Curve, Draw, Raster}

  @width 200
  @height 100
  @protocols [:braille, :kitty, :sixel, :iterm2]

  def run([]), do: run_all()
  def run(["all"]), do: run_all()
  def run(["auto"]), do: render(Capability.detect())
  def run([name]), do: render(String.to_atom(name))

  defp run_all do
    IO.puts("FrenchCurve render demo — #{@width}x#{@height}px")
    IO.puts("detected backend: #{Capability.detect()}")
    Enum.each(@protocols, &render/1)
  end

  defp render(protocol) when protocol in @protocols do
    banner(protocol)
    IO.puts(FrenchCurve.to_terminal(raster(), protocol))
  end

  defp render(protocol) do
    IO.puts("unknown protocol #{inspect(protocol)} — use one of #{inspect(@protocols)}, auto, all")
  end

  defp banner(protocol), do: IO.puts("\n=== #{protocol} ===")

  defp raster do
    Raster.new(@width, @height)
    |> axis()
    |> wave(&:math.sin/1, {0, 200, 255, 255})
    |> wave(&:math.cos/1, {255, 150, 80, 255})
  end

  defp axis(raster) do
    mid = div(@height, 2)
    Draw.line(raster, {0, mid}, {@width - 1, mid}, {70, 70, 90, 255})
  end

  defp wave(raster, fun, color) do
    points =
      for i <- 0..15 do
        t = i / 15
        x = t * (@width - 1)
        y = (@height - 1) / 2 - fun.(t * 4 * :math.pi()) * (@height - 1) / 2 * 0.85
        {x, y}
      end

    smoothed = points |> Curve.catmull_rom(samples: 24) |> Curve.to_pixels()
    Draw.polyline(raster, smoothed, color)
  end
end

RenderDemo.run(System.argv())
