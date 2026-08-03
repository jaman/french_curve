defmodule FrenchCurve.Capability do
  @moduledoc """
  Chooses a graphics protocol from the environment and maps it to a backend module.

  Detection reads `KITTY_WINDOW_ID`, `TERM`, `TERM_PROGRAM`, `TERM_PROGRAM_VERSION` and
  `KONSOLE_VERSION`. The first matching rule wins, in this order:

  | environment | protocol |
  |---|---|
  | `KITTY_WINDOW_ID` set | `:kitty` |
  | `TERM` contains `kitty` or `ghostty` | `:kitty` |
  | `TERM_PROGRAM` is `WezTerm` | `:kitty` |
  | `TERM_PROGRAM` is `iTerm.app` and `TERM_PROGRAM_VERSION` is 3.5 or later | `:kitty` |
  | `TERM_PROGRAM` is `iTerm.app` | `:iterm2` |
  | `KONSOLE_VERSION` set | `:sixel` |
  | `TERM` contains `foot` or `mlterm` | `:sixel` |
  | anything else | `:braille` |

  `:braille` is the fallback because it needs no graphics support at all.

  A terminal detected as `:kitty` does not necessarily speak all of the protocol — ask
  `placements?/1` before storing an image under an id and placing it.

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
      fn env -> iterm_kitty?(env) && :kitty end,
      fn env -> env["TERM_PROGRAM"] == "iTerm.app" && :iterm2 end,
      fn env -> env["KONSOLE_VERSION"] && :sixel end,
      fn env -> term_contains?(env, "foot") && :sixel end,
      fn env -> term_contains?(env, "mlterm") && :sixel end
    ]
  end

  @doc """
  Whether this terminal keeps images under an id and draws them again by placement.

  `detect/1` saying `:kitty` does not mean the whole protocol is there. iTerm from 3.5 speaks
  enough of it to transmit and display in one command (`a=T`), which is why it is detected as
  `:kitty` — but it does not keep an image under an id for `FrenchCurve.Backend.Kitty.place/2`
  to draw again, nor delete one by placement. Code that stores an image and then places it
  draws nothing at all there: the first command stores a picture the terminal never shows, and
  the second is not understood.

  So anything animating a region has to ask this before choosing how to draw:

      if FrenchCurve.Capability.placements?() do
        Kitty.delete(id: id, placement: 1) <> Kitty.transmit(raster, id) <> Kitty.place(id)
      else
        Kitty.render(raster, cursor: :keep, quiet: true)
      end

      iex> FrenchCurve.Capability.placements?(%{"TERM" => "xterm-kitty"})
      true
      iex> FrenchCurve.Capability.placements?(%{
      ...>   "TERM_PROGRAM" => "iTerm.app",
      ...>   "TERM_PROGRAM_VERSION" => "3.5.0"
      ...> })
      false
      iex> FrenchCurve.Capability.placements?(%{"TERM" => "xterm-256color"})
      false
  """
  @spec placements?() :: boolean
  def placements?, do: placements?(System.get_env())

  @spec placements?(map) :: boolean
  def placements?(env) when is_map(env), do: detect(env) == :kitty and not iterm_kitty?(env)

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

  @iterm_kitty_from [3, 5]

  defp iterm_kitty?(%{"TERM_PROGRAM" => "iTerm.app"} = env) do
    case version(env["TERM_PROGRAM_VERSION"]) do
      [] -> false
      parts -> parts >= @iterm_kitty_from
    end
  end

  defp iterm_kitty?(_env), do: false

  defp version(nil), do: []

  defp version(text) do
    text
    |> String.split(".")
    |> Enum.map(&Integer.parse/1)
    |> Enum.take_while(&match?({_number, _rest}, &1))
    |> Enum.map(&elem(&1, 0))
  end
end
