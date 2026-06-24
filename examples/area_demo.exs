defmodule AreaDemo do
  alias FrenchCurve.{Capability, Chart}

  @data [3, 5, 4, 7, 6, 9, 8, 11, 9, 12, 10, 13, 11, 14, 12, 15]
  @width 220
  @height 100
  @protocols [:braille, :kitty, :sixel, :iterm2]

  def run([]), do: run_all()
  def run(["all"]), do: run_all()
  def run(["auto"]), do: render(Capability.detect())
  def run([name]), do: render(String.to_atom(name))

  defp run_all do
    IO.puts("FrenchCurve area chart demo — #{@width}x#{@height}px")
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
    Chart.area(@data,
      width: @width,
      height: @height,
      color: {80, 220, 140, 255},
      fill_opacity: 0.35,
      smooth: true
    )
  end
end

AreaDemo.run(System.argv())
