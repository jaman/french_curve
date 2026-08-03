defmodule FrenchCurve.CapabilityTest do
  use ExUnit.Case, async: true

  alias FrenchCurve.Backend
  alias FrenchCurve.Capability

  doctest FrenchCurve.Capability

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

    test "wezterm is recognised by its pane id when TERM_PROGRAM is stripped" do
      assert Capability.detect(%{"WEZTERM_PANE" => "0"}) == :kitty
      assert Capability.detect(%{"TERM" => "xterm-256color", "WEZTERM_PANE" => "3"}) == :kitty
    end

    test "iterm is recognised over ssh by the locale variable it forwards" do
      assert Capability.detect(%{"LC_TERMINAL" => "iTerm2"}) == :iterm2

      assert Capability.detect(%{"TERM" => "xterm-256color", "LC_TERMINAL" => "iTerm2"}) ==
               :iterm2
    end

    test "another terminal's LC_TERMINAL is not iterm" do
      assert Capability.detect(%{"LC_TERMINAL" => "Alacritty"}) == :braille
    end

    test "a variable exported empty counts as unset" do
      assert Capability.detect(%{"KITTY_WINDOW_ID" => ""}) == :braille
      assert Capability.detect(%{"KONSOLE_VERSION" => ""}) == :braille
      assert Capability.detect(%{"WEZTERM_PANE" => ""}) == :braille
    end
  end

  describe "probe/0" do
    test "asks the terminal its name and then its attributes" do
      assert Capability.probe() == "\e[>q\e[c"
    end
  end

  describe "probe_complete?/1" do
    test "the attributes reply ends the exchange" do
      assert Capability.probe_complete?("\e[?62;4;6c")
      assert Capability.probe_complete?("\eP>|kitty(0.32.2)\e\\\e[?62;22c")
    end

    test "a name on its own is not the end, since attributes follow" do
      refute Capability.probe_complete?("\eP>|kitty(0.32.2)\e\\")
    end

    test "a partial reply is not the end" do
      refute Capability.probe_complete?("")
      refute Capability.probe_complete?("\e[?62;4")
      refute Capability.probe_complete?("\eP>|iTerm2 3.5.0")
    end
  end

  describe "from_probe/1 reads the terminal's name" do
    test "kitty" do
      assert Capability.from_probe("\eP>|kitty(0.32.2)\e\\\e[?62;22c") == :kitty
    end

    test "ghostty" do
      assert Capability.from_probe("\eP>|ghostty 1.0.0\e\\\e[?62;22c") == :kitty
    end

    test "wezterm" do
      assert Capability.from_probe("\eP>|WezTerm 20240203-110809\e\\\e[?62;4c") == :kitty
    end

    test "iterm2 gets its own protocol even though it answers kitty's query" do
      assert Capability.from_probe("\eP>|iTerm2 3.5.0\e\\\e[?62;22c") == :iterm2
    end

    test "the name is read whatever its case" do
      assert Capability.from_probe("\eP>|KITTY(0.32)\e\\\e[?62c") == :kitty
      assert Capability.from_probe("\eP>|iterm2 3.5\e\\\e[?62c") == :iterm2
    end
  end

  describe "from_probe/1 falls back to the attributes reply" do
    test "a terminal reporting sixel support gets sixel" do
      assert Capability.from_probe("\e[?62;4;6c") == :sixel
    end

    test "sixel is found wherever it sits among the attributes" do
      assert Capability.from_probe("\e[?4c") == :sixel
      assert Capability.from_probe("\e[?62;4c") == :sixel
      assert Capability.from_probe("\e[?1;2;4c") == :sixel
    end

    test "an attribute merely containing the digit is not sixel" do
      assert Capability.from_probe("\e[?64;41c") == nil
      assert Capability.from_probe("\e[?62;14c") == nil
    end

    test "a terminal with no sixel and no name it knows gets nothing" do
      assert Capability.from_probe("\e[?62;22c") == nil
      assert Capability.from_probe("\eP>|XTerm(389)\e\\\e[?62;22c") == nil
    end

    test "a terminal that said nothing at all gets nothing" do
      assert Capability.from_probe("") == nil
    end

    test "a name that means kitty wins over attributes that mention sixel" do
      assert Capability.from_probe("\eP>|kitty(0.32.2)\e\\\e[?62;4c") == :kitty
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
