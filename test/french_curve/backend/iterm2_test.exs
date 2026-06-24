defmodule FrenchCurve.Backend.Iterm2Test do
  use ExUnit.Case, async: true

  alias FrenchCurve.Backend.Iterm2
  alias FrenchCurve.Raster

  @png_signature <<137, 80, 78, 71, 13, 10, 26, 10>>

  test "wraps a PNG payload in an iTerm2 inline-image escape" do
    raster = Raster.put_pixel(Raster.new(1, 1), 0, 0, {255, 0, 0, 255})
    out = Iterm2.render(raster)

    assert String.starts_with?(out, "\e]1337;File=inline=1")
    assert String.ends_with?(out, "\a")
    assert out =~ "size="
  end

  test "the embedded payload decodes to a PNG" do
    raster = Raster.put_pixel(Raster.new(1, 1), 0, 0, {255, 0, 0, 255})
    out = Iterm2.render(raster)

    [_header, after_colon] = String.split(out, ":", parts: 2)
    png = after_colon |> String.replace_trailing("\a", "") |> Base.decode64!()

    assert String.starts_with?(png, @png_signature)
    assert out =~ "size=#{byte_size(png)}"
  end

  test "fit: {cols, rows} sizes the inline image in cells" do
    out = Iterm2.render(Raster.new(4, 4), fit: {12, 6})
    assert out =~ "width=12;height=6"
    assert out =~ "preserveAspectRatio=0"
  end

  test "omits sizing when no fit is requested" do
    refute Iterm2.render(Raster.new(4, 4)) =~ "width="
  end
end
