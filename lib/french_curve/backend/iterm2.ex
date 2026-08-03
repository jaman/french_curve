defmodule FrenchCurve.Backend.Iterm2 do
  @moduledoc """
  Renders a raster with iTerm2's inline-image protocol, as a base64 PNG in an OSC 1337
  sequence.

  True RGBA, so transparency is kept. The protocol has no stored images: every draw sends
  the whole picture, which is why `FrenchCurve.Sprite.upload/3` does nothing here.

      IO.write(FrenchCurve.Backend.Iterm2.render(raster, fit: {20, 10}))
  """

  alias FrenchCurve.{Png, Raster}

  @doc """
  Returns the escape sequence that draws `raster` at the cursor.

  The raster is encoded as a PNG by `FrenchCurve.Png.encode/3` and base64-wrapped.

  ## Options

    * `:fit` — `{cols, rows}`, the cell box to scale the image into. Sizing is in cells
      natively, so no cell-pixel size is needed. Aspect ratio is not preserved: the image
      is stretched to fill the box. Omitted by default, which leaves iTerm2 to size the
      image from its pixel dimensions.
  """
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
