defmodule FrenchCurve.Capability do
  @moduledoc false

  alias FrenchCurve.Backend

  @cache_key {__MODULE__, :detected}

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

  @spec backend(atom) :: module
  def backend(:kitty), do: Backend.Kitty
  def backend(:sixel), do: Backend.Sixel
  def backend(:iterm2), do: Backend.Iterm2
  def backend(:braille), do: Backend.Braille

  defp term_contains?(env, needle) do
    String.contains?(env["TERM"] || "", needle)
  end
end
