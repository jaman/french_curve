defmodule FrenchCurve.Capability do
  @moduledoc """
  Chooses a graphics protocol from the environment and maps it to a backend module.

  Detection reads `KITTY_WINDOW_ID`, `TERM`, `TERM_PROGRAM` and `KONSOLE_VERSION`. The first matching rule wins, in this order:

  | environment | protocol |
  |---|---|
  | `KITTY_WINDOW_ID` set | `:kitty` |
  | `TERM` contains `kitty` or `ghostty` | `:kitty` |
  | `TERM_PROGRAM` is `WezTerm` | `:kitty` |
  | `TERM_PROGRAM` is `iTerm.app` | `:iterm2` |
  | `KONSOLE_VERSION` set | `:sixel` |
  | `TERM` contains `foot` or `mlterm` | `:sixel` |
  | anything else | `:braille` |

  `:braille` is the fallback because it needs no graphics support at all.

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
  @spec detect(map) :: atom
  def detect(env) when is_map(env) do
    Enum.find_value(matchers(), :braille, & &1.(env))
  end

  defp matchers do
    [
      fn env -> env["KITTY_WINDOW_ID"] && :kitty end,
      fn env -> term_contains?(env, "kitty") && :kitty end,
      fn env -> term_contains?(env, "ghostty") && :kitty end,
      fn env -> env["TERM_PROGRAM"] == "WezTerm" && :kitty end,
      fn env -> env["TERM_PROGRAM"] == "iTerm.app" && :iterm2 end,
      fn env -> env["KONSOLE_VERSION"] && :sixel end,
      fn env -> term_contains?(env, "foot") && :sixel end,
      fn env -> term_contains?(env, "mlterm") && :sixel end
    ]
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

  # Terminals that answer to the kitty protocol without keeping images under an id. Nothing is
  # here today — iTerm was, and is now detected as :iterm2 instead — but the question is real
  # and this is where the answer goes.
  defp partial_kitty?(_env), do: false
end
