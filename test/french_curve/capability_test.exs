defmodule FrenchCurve.CapabilityTest do
  use ExUnit.Case, async: true

  alias FrenchCurve.Backend
  alias FrenchCurve.Capability

  describe "detect/1" do
    test "kitty via window id" do
      assert Capability.detect(%{"KITTY_WINDOW_ID" => "1"}) == :kitty
    end

    test "kitty via TERM" do
      assert Capability.detect(%{"TERM" => "xterm-kitty"}) == :kitty
    end

    test "ghostty maps to kitty protocol" do
      assert Capability.detect(%{"TERM" => "xterm-ghostty"}) == :kitty
    end

    test "wezterm maps to kitty protocol" do
      assert Capability.detect(%{"TERM_PROGRAM" => "WezTerm"}) == :kitty
    end

    test "iterm uses its own protocol" do
      assert Capability.detect(%{"TERM_PROGRAM" => "iTerm.app"}) == :iterm2
    end

    test "foot and konsole use sixel" do
      assert Capability.detect(%{"TERM" => "foot"}) == :sixel
      assert Capability.detect(%{"KONSOLE_VERSION" => "220400"}) == :sixel
    end

    test "unknown terminals fall back to braille" do
      assert Capability.detect(%{"TERM" => "xterm-256color"}) == :braille
      assert Capability.detect(%{}) == :braille
    end
  end

  describe "backend/1" do
    test "maps protocols to their modules" do
      assert Capability.backend(:kitty) == Backend.Kitty
      assert Capability.backend(:sixel) == Backend.Sixel
      assert Capability.backend(:iterm2) == Backend.Iterm2
      assert Capability.backend(:braille) == Backend.Braille
    end
  end

  describe "detect/0" do
    test "returns a supported protocol" do
      assert Capability.detect() in [:kitty, :sixel, :iterm2, :braille]
    end
  end
end
