defmodule FrenchCurve do
  @moduledoc false

  alias FrenchCurve.Backend.Braille
  alias FrenchCurve.{Capability, Raster}

  @spec render(Raster.t(), keyword) :: term
  def render(%Raster{} = raster, opts \\ []) do
    protocol = Keyword.get(opts, :protocol) || Capability.detect()
    render(raster, protocol, opts)
  end

  @spec render(Raster.t(), atom, keyword) :: term
  def render(%Raster{} = raster, protocol, opts) when is_atom(protocol) do
    backend = Capability.backend(protocol)
    backend.render(raster, opts)
  end

  @spec to_terminal(Raster.t(), atom, keyword) :: binary
  def to_terminal(raster, protocol, opts \\ [])

  def to_terminal(%Raster{} = raster, :braille, opts) do
    raster |> render(:braille, opts) |> Braille.to_ansi()
  end

  def to_terminal(%Raster{} = raster, protocol, opts) when is_atom(protocol) do
    render(raster, protocol, opts)
  end
end
