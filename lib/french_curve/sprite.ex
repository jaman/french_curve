defmodule FrenchCurve.Sprite do
  @moduledoc """
  A raster that is drawn many times, uploaded once where the protocol allows it.

  Under `:kitty` a sprite is transmitted to the terminal once under a numeric id and then
  stamped by reference, so repeated draws cost an id rather than a screenful of pixels.
  The other three protocols have no stored-image concept: `upload/3` and `delete/3` are
  no-ops returning `""`, and `place/3` re-emits the pixels every time. The same call
  sequence therefore works everywhere.

      sprite = FrenchCurve.Sprite.new(raster)

      IO.write(FrenchCurve.Sprite.upload(sprite, :kitty))
      IO.write(FrenchCurve.Sprite.place(sprite, :kitty, fit: {4, 2}))

  `FrenchCurve.Sprite.Registry` tracks which sprites have already been uploaded so a
  render loop can call it unconditionally.
  """

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

  @doc """
  Wraps `raster` as a sprite, finalizing its dense pixel buffer.

  `width` and `height` are taken from the raster. Drawing into `sprite.raster` afterwards
  will not change the id, so build the raster fully before calling this.

  ## Options

    * `:id` — the positive integer the terminal stores the image under. Defaults to a hash
      of the pixels, so two sprites with identical contents share an id and upload once.
      Pass an explicit id only if you manage the terminal's id space yourself; two
      different images sharing an id will overwrite each other.
  """
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

  @doc """
  Returns the bytes that store the sprite's pixels in the terminal without displaying them.

  Under `:kitty` this is a transmit sequence carrying the sprite's id; `opts` are
  `FrenchCurve.Backend.Kitty.transmit/3`'s, of which `:compress` is the useful one. Every
  other protocol returns `""`, as none has anywhere to store an image.

  Send this once per sprite before the first `place/3`.
  """
  @spec upload(t, atom, keyword) :: binary
  def upload(sprite, protocol, opts \\ [])

  def upload(%__MODULE__{} = sprite, :kitty, opts),
    do: Kitty.transmit(sprite.raster, sprite.id, opts)

  def upload(%__MODULE__{}, protocol, _opts) when is_atom(protocol), do: ""

  @doc """
  Returns the bytes that draw the sprite at the cursor.

  Under `:kitty` this references the uploaded image by id and takes
  `FrenchCurve.Backend.Kitty.place/2`'s options (`:fit`, `:z`, `:placement`); `upload/3`
  must have been sent first or the terminal has nothing to draw. Under `:sixel` and
  `:iterm2` the pixels are re-encoded on every call, taking that backend's `render/2`
  options. Under `:braille` the result is an ANSI string of braille characters.

  `protocol` must be one of the four; any other atom raises `FunctionClauseError`.
  """
  @spec place(t, atom, keyword) :: binary
  def place(sprite, protocol, opts \\ [])
  def place(%__MODULE__{} = sprite, :kitty, opts), do: Kitty.place(sprite.id, opts)
  def place(%__MODULE__{} = sprite, :sixel, opts), do: Sixel.render(sprite.raster, opts)
  def place(%__MODULE__{} = sprite, :iterm2, opts), do: Iterm2.render(sprite.raster, opts)

  def place(%__MODULE__{} = sprite, :braille, opts) do
    sprite.raster |> Braille.render(opts) |> Braille.to_ansi()
  end

  @doc """
  Returns the bytes that release the sprite's stored image from the terminal.

  Under `:kitty` this deletes by the sprite's id; pass `:placement` in `opts` to target a
  single placement. Every other protocol returns `""`. A sprite deleted this way must be
  uploaded again before it can be placed.
  """
  @spec delete(t, atom, keyword) :: binary
  def delete(sprite, protocol, opts \\ [])

  def delete(%__MODULE__{} = sprite, :kitty, opts) do
    Kitty.delete(Keyword.put(opts, :id, sprite.id))
  end

  def delete(%__MODULE__{}, protocol, _opts) when is_atom(protocol), do: ""

  defp content_id(raster), do: :erlang.phash2(Raster.to_rgba_binary(raster)) + 1
end
