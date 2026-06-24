defmodule AnimatedArea do
  alias FrenchCurve.Chart

  @width 220
  @height 80
  @default_frames 160
  @fps 24
  @protocols [:braille, :kitty, :sixel, :iterm2]

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

  defp animate(protocol, frames) do
    IO.write("\e[2J\e[?25l")

    try do
      Enum.each(0..(frames - 1)//1, fn frame -> draw(protocol, frame) end)
    after
      IO.write(reset(protocol) <> "\e[?25h")
    end
  end

  defp draw(protocol, frame) do
    body = FrenchCurve.to_terminal(raster(frame), protocol, [])
    IO.write(clear(protocol) <> body)
    Process.sleep(div(1000, @fps))
  end

  defp clear(:braille), do: "\e[H"
  defp clear(:kitty), do: "\e_Ga=d\e\\\e[H"
  defp clear(_protocol), do: "\e[2J\e[H"

  defp reset(:kitty), do: "\e_Ga=d\e\\\e[2J\e[H"
  defp reset(_protocol), do: "\e[2J\e[H"

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
