defmodule FrenchCurveTest do
  use ExUnit.Case, async: true

  alias FrenchCurve.Raster

  defp sample, do: Raster.put_pixel(Raster.new(2, 4), 0, 0, {255, 0, 0, 255})

  describe "render/3 with an explicit protocol" do
    test "braille returns cell rows" do
      assert [[{_char, _color} | _] | _] = FrenchCurve.render(sample(), :braille, [])
    end

    test "kitty returns an escape sequence" do
      assert String.starts_with?(FrenchCurve.render(sample(), :kitty, []), "\e_G")
    end

    test "sixel returns a DCS string" do
      assert String.starts_with?(FrenchCurve.render(sample(), :sixel, []), "\eP")
    end

    test "iterm2 returns an inline-image escape" do
      assert String.starts_with?(FrenchCurve.render(sample(), :iterm2, []), "\e]1337")
    end
  end

  describe "render/2" do
    test "honors an explicit :protocol option" do
      assert String.starts_with?(FrenchCurve.render(sample(), protocol: :kitty), "\e_G")
    end

    test "auto-detects when no protocol is given" do
      assert FrenchCurve.render(sample()) != nil
    end
  end

  describe "to_terminal/3" do
    test "braille returns a printable ANSI string, not cell rows" do
      output = FrenchCurve.to_terminal(sample(), :braille)
      assert is_binary(output)
      assert output =~ ~r/[\x{2800}-\x{28FF}]/u
    end

    test "pixel backends return their escape string unchanged" do
      assert String.starts_with?(FrenchCurve.to_terminal(sample(), :kitty), "\e_G")
      assert String.starts_with?(FrenchCurve.to_terminal(sample(), :sixel), "\eP")
      assert String.starts_with?(FrenchCurve.to_terminal(sample(), :iterm2), "\e]1337")
    end
  end
end
