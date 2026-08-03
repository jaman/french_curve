defmodule AnimatedArea do
  alias FrenchCurve.Chart

  @width 220
  @height 80
  @default_frames 160
  @fps 24
  @protocols [:braille, :kitty, :sixel, :iterm2]
  @region :area_chart

  def run([]), do: animate(:braille, @default_frames)

  def run([arg]) do
    if arg in protocol_names() do
      animate(String.to_atom(arg), @default_frames)
    else
      animate(:braille, String.to_integer(arg))
    end
  end

  def run([protocol, frames]) do
    animate(String.to_atom(protocol), String.to_integer(frames))
  end

  defp protocol_names, do: Enum.map(@protocols, &Atom.to_string/1)

  defp animate(_protocol, frames) when frames < 1, do: :ok

  defp animate(protocol, frames) do
    IO.write("\e[2J\e[?25l")
    clear = draw(protocol, 0)

    try do
      Enum.each(1..(frames - 1)//1, &draw(protocol, &1))
    after
      IO.write(clear <> "\e[2J\e[H\e[?25h")
    end
  end

  defp draw(protocol, index) do
    raster = raster(index)
    IO.write("\e[H")

    clear = paint(FrenchCurve.frame(raster, @region, protocol: protocol), raster, protocol)

    Process.sleep(div(1000, @fps))
    clear
  end

  defp paint(nil, raster, protocol) do
    IO.write(FrenchCurve.to_terminal(raster, protocol))
    ""
  end

  defp paint({paint, clear, _place}, _raster, _protocol) do
    IO.write(paint)
    clear
  end

  defp raster(frame) do
    phase = frame * 0.18

    data =
      for i <- 0..47 do
        :math.sin(i * 0.28 + phase) + 0.4 * :math.sin(i * 0.7 + phase * 1.6)
      end

    Chart.area(data,
      width: @width,
      height: @height,
      color: {0, 200, 255, 255},
      fill_opacity: 0.35,
      smooth: true,
      min: -1.6,
      max: 1.6
    )
  end
end

AnimatedArea.run(System.argv())
