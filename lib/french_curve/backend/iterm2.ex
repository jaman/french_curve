defmodule FrenchCurve.Backend.Iterm2 do
  @moduledoc false

  alias FrenchCurve.{Png, Raster}

  @spec render(Raster.t(), keyword) :: binary
  def render(%Raster{} = raster, opts \\ []) do
    {width, height} = Raster.dimensions(raster)
    png = Png.encode(width, height, Raster.to_rgba_binary(raster))
    encoded = Base.encode64(png)
    fit = fit_dimensions(Keyword.get(opts, :fit))

    "\e]1337;File=inline=1;size=#{byte_size(png)}#{fit}:" <> encoded <> "\a"
  end

  defp fit_dimensions(nil), do: ""
  defp fit_dimensions({cols, rows}), do: ";width=#{cols};height=#{rows};preserveAspectRatio=0"
end
