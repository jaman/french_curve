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

    test "iterm falls back to its own protocol when it cannot say it is new enough" do
      assert Capability.detect(%{"TERM_PROGRAM" => "iTerm.app"}) == :iterm2

      assert Capability.detect(%{"TERM_PROGRAM" => "iTerm.app", "TERM_PROGRAM_VERSION" => ""}) ==
               :iterm2
    end

    test "every iterm uses its own protocol, whatever version it reports" do
      # 3.5 and later understand kitty's transmit-and-display and were detected as :kitty for a
      # while. They have no way to remove such an image, though — it is an overlay rather than
      # cells, so it outlives the text drawn over it and the screen it was drawn on, and ends up
      # smeared across the terminal after the program exits. Inline images are cells and behave.
      for version <- ["3.5", "3.5.0", "3.6.11", "4.0", "3.10.0", "3.6.11beta", "3.4.23", ""] do
        assert Capability.detect(%{
                 "TERM_PROGRAM" => "iTerm.app",
                 "TERM_PROGRAM_VERSION" => version
               }) == :iterm2,
               "expected iTerm #{inspect(version)} to use its own inline protocol"
      end
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

  describe "placements?/1" do
    test "a real kitty keeps images under an id" do
      assert Capability.placements?(%{"TERM" => "xterm-kitty"})
      assert Capability.placements?(%{"KITTY_WINDOW_ID" => "1"})
    end

    test "iTerm has none, at any version" do
      for version <- ~w(3.4.23 3.5.0 3.5.11 4.0 5.1.2) do
        env = %{"TERM_PROGRAM" => "iTerm.app", "TERM_PROGRAM_VERSION" => version}

        refute Capability.placements?(env), "iTerm #{version}"
      end
    end

    test "a terminal with no graphics at all has no placements either" do
      refute Capability.placements?(%{"TERM" => "xterm-256color"})
      refute Capability.placements?(%{})
    end

    test "sixel is not kitty and so has none" do
      refute Capability.placements?(%{"KONSOLE_VERSION" => "22"})
    end

    test "wezterm and ghostty keep them" do
      assert Capability.placements?(%{"TERM_PROGRAM" => "WezTerm"})
      assert Capability.placements?(%{"TERM" => "xterm-ghostty"})
    end
  end
end
