defmodule FrenchCurve.Sprite do
  @moduledoc false

  alias FrenchCurve.Backend.{Braille, Iterm2, Kitty, Sixel}
  alias FrenchCurve.Raster

  @enforce_keys [:id, :raster, :width, :height]
  defstruct [:id, :raster, :width, :height]

  @type t :: %__MODULE__{
          id: pos_integer,
          raster: Raster.t(),
          width: pos_integer,
          height: pos_integer
        }

  @spec new(Raster.t(), keyword) :: t
  def new(%Raster{} = raster, opts \\ []) do
    finalized = Raster.finalize(raster)
    {width, height} = Raster.dimensions(finalized)

    %__MODULE__{
      id: Keyword.get(opts, :id, content_id(finalized)),
      raster: finalized,
      width: width,
      height: height
    }
  end

  @spec upload(t, atom) :: binary
  def upload(%__MODULE__{} = sprite, :kitty), do: Kitty.transmit(sprite.raster, sprite.id)
  def upload(%__MODULE__{}, protocol) when is_atom(protocol), do: ""

  @spec place(t, atom, keyword) :: binary
  def place(sprite, protocol, opts \\ [])
  def place(%__MODULE__{} = sprite, :kitty, opts), do: Kitty.place(sprite.id, opts)
  def place(%__MODULE__{} = sprite, :sixel, opts), do: Sixel.render(sprite.raster, opts)
  def place(%__MODULE__{} = sprite, :iterm2, opts), do: Iterm2.render(sprite.raster, opts)

  def place(%__MODULE__{} = sprite, :braille, opts) do
    sprite.raster |> Braille.render(opts) |> Braille.to_ansi()
  end

  @spec delete(t, atom, keyword) :: binary
  def delete(sprite, protocol, opts \\ [])

  def delete(%__MODULE__{} = sprite, :kitty, opts) do
    Kitty.delete(Keyword.put(opts, :id, sprite.id))
  end

  def delete(%__MODULE__{}, protocol, _opts) when is_atom(protocol), do: ""

  defp content_id(raster), do: :erlang.phash2(Raster.to_rgba_binary(raster)) + 1
end
