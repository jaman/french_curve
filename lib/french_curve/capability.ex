defmodule FrenchCurve.Capability do
  @moduledoc """
  Chooses a graphics protocol from the environment and maps it to a backend module.

  Detection reads `KITTY_WINDOW_ID`, `TERM`, `TERM_PROGRAM`, `WEZTERM_PANE`, `LC_TERMINAL` and
  `KONSOLE_VERSION`. A variable exported empty counts as unset. The first matching rule wins,
  in this order:

  | environment | protocol |
  |---|---|
  | `KITTY_WINDOW_ID` set | `:kitty` |
  | `TERM` contains `kitty` or `ghostty` | `:kitty` |
  | `TERM_PROGRAM` is `WezTerm` | `:kitty` |
  | `WEZTERM_PANE` set | `:kitty` |
  | `TERM_PROGRAM` is `iTerm.app` | `:iterm2` |
  | `LC_TERMINAL` is `iTerm2` | `:iterm2` |
  | `KONSOLE_VERSION` set | `:sixel` |
  | `TERM` contains `foot` or `mlterm` | `:sixel` |
  | anything else | `:braille` |

  `:braille` is the fallback because it needs no graphics support at all.

  `WEZTERM_PANE` and `LC_TERMINAL` cover terminals whose `TERM_PROGRAM` did not survive the
  trip: multiplexers drop it, and ssh forwards only the variables its client is configured to
  send, which for iTerm2 is `LC_TERMINAL` under the usual `SendEnv LC_*`. Detecting a remote
  client therefore means passing that session's environment to `detect/1`, not the
  environment of the host the program runs on.

  A terminal detected as `:kitty` does not necessarily speak all of the protocol — ask
  `placements?/1` before storing an image under an id and placing it.

  ## Why iTerm is not `:kitty`

  iTerm from 3.5 does understand kitty's transmit-and-display, and was detected as `:kitty` for
  a while on the strength of it. That is a trap. A kitty image is an **overlay**: it is not made
  of cells, so writing text over it does not rub it out, leaving the alternate screen does not
  discard it, and the only thing that removes it is an explicit delete addressed to its id —
  which iTerm does not implement. Images pile up over the text while the program runs and are
  still on the screen after it exits.

  Its own protocol has none of that problem, because an inline image *is* cells: it scrolls,
  gets overwritten and disappears with the screen it was drawn on, exactly like text.

      case FrenchCurve.Capability.detect() do
        :braille -> IO.write(FrenchCurve.to_terminal(raster, :braille))
        protocol -> IO.write(FrenchCurve.to_terminal(raster, protocol))
      end
  """

  alias FrenchCurve.Backend

  @cache_key {__MODULE__, :detected}

  @doc """
  Detects the protocol for the current OS environment.

  The result is computed once and cached in `:persistent_term` under
  `{FrenchCurve.Capability, :detected}` for the life of the VM, so a later change to the
  environment is not picked up. Use `detect/1` to detect against a specific environment.

  Returns `:kitty`, `:sixel`, `:iterm2` or `:braille`.
  """
  @spec detect() :: atom
  def detect do
    case :persistent_term.get(@cache_key, :undetected) do
      :undetected ->
        result = detect(System.get_env())
        :persistent_term.put(@cache_key, result)
        result

      cached ->
        cached
    end
  end

  @doc """
  Detects the protocol for `env`, a map of environment variable name to string value.

  Uncached, and missing keys are treated as unset. Returns `:kitty`, `:sixel`, `:iterm2`
  or `:braille`; `:braille` when no rule matches.

      iex> FrenchCurve.Capability.detect(%{"TERM" => "xterm-kitty"})
      :kitty
  """
  @rules [
    {:set, "KITTY_WINDOW_ID", :kitty},
    {:term, "kitty", :kitty},
    {:term, "ghostty", :kitty},
    {:equals, "TERM_PROGRAM", "WezTerm", :kitty},
    {:set, "WEZTERM_PANE", :kitty},
    {:equals, "TERM_PROGRAM", "iTerm.app", :iterm2},
    {:equals, "LC_TERMINAL", "iTerm2", :iterm2},
    {:set, "KONSOLE_VERSION", :sixel},
    {:term, "foot", :sixel},
    {:term, "mlterm", :sixel}
  ]

  @spec detect(map) :: atom
  def detect(env) when is_map(env) do
    Enum.find_value(@rules, :braille, &matched(&1, env))
  end

  defp matched({:set, name, protocol}, env), do: set?(env, name) && protocol
  defp matched({:term, needle, protocol}, env), do: term_contains?(env, needle) && protocol
  defp matched({:equals, name, value, protocol}, env), do: env[name] == value && protocol

  @probe "\e[>q\e[c"

  @names [
    {"kitty", :kitty},
    {"ghostty", :kitty},
    {"wezterm", :kitty},
    {"iterm2", :iterm2},
    {"foot", :sixel},
    {"mlterm", :sixel}
  ]

  @sixel_attribute "4"

  @doc """
  The bytes to write to a terminal to ask what it supports.

  Two queries: XTVERSION (`CSI > q`), which a terminal answers with its name, and
  primary device attributes (`CSI c`), which it answers with a list of features.
  The attributes reply is what `probe_complete?/1` watches for, because nearly
  every terminal answers it while only some answer XTVERSION — so it arrives last
  and marks the end of the exchange.

  A terminal that answers neither says nothing at all, which is why a caller must
  also give up on a timeout.

      iex> FrenchCurve.Capability.probe()
      "\\e[>q\\e[c"

  """
  @spec probe() :: binary
  def probe, do: @probe

  @doc """
  Whether `replies` contains the device attributes answer that ends the exchange.

      iex> FrenchCurve.Capability.probe_complete?("\\e[?62;4c")
      true

      iex> FrenchCurve.Capability.probe_complete?("\\eP>|kitty(0.32.2)\\e\\\\")
      false

  """
  @spec probe_complete?(binary) :: boolean
  def probe_complete?(replies) when is_binary(replies) do
    Regex.match?(~r/\e\[\?[0-9;]*c/, replies)
  end

  @doc """
  The protocol `replies` implies, or `nil` when they name nothing usable.

  The terminal's own name wins: a terminal that says it is kitty, ghostty or
  WezTerm gets `:kitty`, and one that says it is iTerm2 gets `:iterm2` even though
  it answers kitty's queries. Only when the name is absent or unrecognised do the
  device attributes decide, where a `4` among them is sixel support.

      iex> FrenchCurve.Capability.from_probe("\\eP>|kitty(0.32.2)\\e\\\\\\e[?62;22c")
      :kitty

      iex> FrenchCurve.Capability.from_probe("\\e[?62;4;6c")
      :sixel

      iex> FrenchCurve.Capability.from_probe("\\e[?62;22c")
      nil

  """
  @spec from_probe(binary) :: atom | nil
  def from_probe(replies) when is_binary(replies) do
    named(replies) || sixel_attribute(replies)
  end

  defp named(replies) do
    case Regex.run(~r/\eP>\|([^\e\a]*)/, replies) do
      [_, name] -> protocol_for_name(String.downcase(name))
      nil -> nil
    end
  end

  defp protocol_for_name(name) do
    Enum.find_value(@names, fn {needle, protocol} ->
      String.contains?(name, needle) && protocol
    end)
  end

  defp sixel_attribute(replies) do
    case Regex.run(~r/\e\[\?([0-9;]*)c/, replies) do
      [_, params] -> if @sixel_attribute in String.split(params, ";"), do: :sixel
      nil -> nil
    end
  end

  @doc """
  Whether this terminal keeps images under an id and draws them again by placement.

  `detect/1` saying `:kitty` does not have to mean the whole protocol is there: a terminal can
  understand transmit-and-display (`a=T`) without keeping images under an id for
  `FrenchCurve.Backend.Kitty.place/2` to draw again. Sending one a store and then a placement
  draws nothing at all — it stores a picture it never shows, then is handed a command it does
  not understand.

  `FrenchCurve.frame/3` asks this and picks accordingly; ask it yourself only if you are
  building the sequence by hand.

      iex> FrenchCurve.Capability.placements?(%{"TERM" => "xterm-kitty"})
      true
      iex> FrenchCurve.Capability.placements?(%{"TERM_PROGRAM" => "iTerm.app"})
      false
      iex> FrenchCurve.Capability.placements?(%{"TERM" => "xterm-256color"})
      false
  """
  @spec placements?() :: boolean
  def placements?, do: placements?(System.get_env())

  @doc """
  Whether the terminal described by `env` keeps images under an id and places them.

  As `placements?/0`, against a given environment map rather than the OS one. Uncached.
  """
  @spec placements?(map) :: boolean
  def placements?(env) when is_map(env), do: detect(env) == :kitty and not partial_kitty?(env)

  @doc """
  Returns the backend module implementing `protocol`.

  Accepts `:kitty`, `:sixel`, `:iterm2` and `:braille`; any other value raises
  `FunctionClauseError`. Every returned module exports `render/2` taking a
  `FrenchCurve.Raster` and a keyword list.
  """
  @spec backend(atom) :: module
  def backend(:kitty), do: Backend.Kitty
  def backend(:sixel), do: Backend.Sixel
  def backend(:iterm2), do: Backend.Iterm2
  def backend(:braille), do: Backend.Braille

  defp term_contains?(env, needle) do
    String.contains?(env["TERM"] || "", needle)
  end

  defp set?(env, name), do: env[name] not in [nil, ""]

  defp partial_kitty?(_env), do: false
end
