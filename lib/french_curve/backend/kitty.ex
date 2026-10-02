defmodule FrenchCurve.Backend.Kitty do
  @moduledoc """
  Renders a raster with the kitty graphics protocol, as raw RGBA (`f=32`) in APC sequences.

  True RGBA, so transparency is kept. Alone among the four backends this one has a stored
  image: `transmit/3` puts pixels in the terminal under a numeric id and `place/2` stamps
  that id anywhere, so a repeated image costs one small sequence per draw. `render/2` is
  the one-shot form that transmits and displays in a single call.

  Pixels are base64-encoded and split into 4096-byte chunks, each carrying its own escape
  sequence.

  `transmit/3`, `place/2` and `delete/1` suppress the terminal's acknowledgement (`q=2`)
  on every chunk they emit, so none of them provokes a reply on stdin, where it would
  reach the application as a run of keystrokes. `render/2` does not set it, so a terminal
  that acknowledges by default will answer a `render/2` call; read and discard that reply,
  or use `transmit/3` with `place/2` on an input-reading application.

      IO.write(FrenchCurve.Backend.Kitty.transmit(raster, 42, compress: true))
      IO.write(FrenchCurve.Backend.Kitty.place(42, fit: {20, 10}, z: 1))

  ## Compression

  `compress: true` deflates the pixels before base64 and tells the terminal so with `o=z`,
  which shrinks both the payload and the number of chunks. It is off by default: the
  protocol makes compression optional and a partial implementation may not support it, so
  turn it on only for terminals you know accept it.
  """

  alias FrenchCurve.{Deflate, Raster}

  @chunk_size 4096

  @doc """
  Returns the sequence that transmits `raster` and displays it at the cursor (`a=T`).

  The image is not stored under an id and cannot be placed again; use `transmit/3` and
  `place/2` for that.

  ## Options

    * `:fit` — `{cols, rows}`, the cell box the terminal scales the image into. Omitted by
      default, which sizes the image from its pixel dimensions.
    * `:compress` — deflate the pixels before base64 and mark the payload `o=z`; an
      integer sets the level `FrenchCurve.Deflate` compresses at, default
      `false`
    * `:cursor` — `:keep` leaves the caret where it was (`C=1`) rather than letting the
      terminal move it past the image, which near the bottom of the screen would scroll.
      Omitted by default, which is the terminal's own behaviour
    * `:quiet` — suppress the terminal's replies (`q=2`), default `false`. Worth setting for
      anything drawn repeatedly, since the replies otherwise arrive as input
    * `:id` — also name the image, so `delete/1` can take it off again. **Set this for anything
      drawn more than once.** A kitty image is an overlay rather than cells: text written over
      it does not rub it out and leaving the alternate screen does not discard it, so an
      unnamed one cannot be removed at all and is still on the screen after the program exits
  """
  @spec render(Raster.t(), keyword) :: binary
  def render(%Raster{} = raster, opts \\ []) do
    {width, height} = Raster.dimensions(raster)

    control =
      "a=T,f=32,s=#{width},v=#{height}" <>
        named(opts) <> fit_control(opts[:fit]) <> compression(opts) <> cursor(opts) <> quiet(opts)

    raster
    |> payload(opts)
    |> emit(control)
  end

  defp named(opts), do: if(opts[:id], do: ",i=#{opts[:id]}", else: "")

  defp cursor(opts), do: if(opts[:cursor] == :keep, do: ",C=1", else: "")

  defp quiet(opts), do: if(opts[:quiet], do: ",q=2", else: "")

  @doc """
  Returns the sequence that stores `raster` under `id` without displaying it (`a=t`).

  `id` is a positive integer naming the image in the terminal until `delete/1`; storing a
  second image under an id already in use replaces the first. Pass the same `id` to
  `place/2` to draw it.

  ## Options

    * `:compress` — deflate the pixels before base64 and mark the payload `o=z`; an
      integer sets the level `FrenchCurve.Deflate` compresses at, default
      `false`

  Sizing is chosen per placement rather than per image, so `:fit` has no effect here and
  belongs on `place/2`.
  """
  @spec transmit(Raster.t(), pos_integer, keyword) :: binary
  def transmit(%Raster{} = raster, id, opts \\ []) do
    {width, height} = Raster.dimensions(raster)
    control = "a=t,i=#{id},f=32,s=#{width},v=#{height},q=2" <> compression(opts)

    raster
    |> payload(opts)
    |> emit(control)
  end

  @doc """
  Returns the sequence that draws the stored image `id` at the cursor (`a=p`).

  `id` must already have been sent by `transmit/3`, or the terminal has nothing to draw.
  The cursor is left where it was (`C=1`), so a placement does not move the caret.

  ## Options

    * `:fit` — `{cols, rows}`, the cell box the terminal scales this placement into
    * `:z` — integer stacking order; higher placements draw over lower ones, and negative
      values sit behind the text
    * `:placement` — integer id for this placement, needed to delete or replace it
      individually. Omitted by default, which lets the terminal assign one.
    * `:x_offset`, `:y_offset` — pixels to shift the image right and down inside the
      cursor's cell, each less than the cell's size in that direction
    * `:source` — `{x, y, width, height}`, the rectangle of the stored image to show, in
      pixels from its top left. The whole image by default.

  Every option is omitted from the sequence when not given, leaving the terminal's default.
  """
  @spec place(pos_integer, keyword) :: binary
  def place(id, opts \\ []) do
    control =
      ["a=p", "i=#{id}", "q=2", "C=1"] ++
        placement_part(opts[:placement]) ++
        z_part(opts[:z]) ++
        fit_part(opts[:fit]) ++
        offset_part(opts[:x_offset], opts[:y_offset]) ++ source_part(opts[:source])

    command(Enum.join(control, ","))
  end

  @doc """
  Returns the sequence that removes placements (`a=d`).

  ## Options

    * `:id` — the image id given to `transmit/3`; removes the image and every placement
      of it. Required unless `:z` is given.
    * `:placement` — with `:id`, delete only this placement, leaving the image stored and
      its other placements alone.
    * `:z` — instead of `:id`, delete every placement at this z-index, of any image,
      keeping the images stored.
  """
  @spec delete(keyword) :: binary
  def delete(opts) do
    control =
      case Keyword.fetch(opts, :z) do
        {:ok, z} ->
          ["a=d", "d=z", "z=#{z}", "q=2"]

        :error ->
          ["a=d", "d=i", "i=#{Keyword.fetch!(opts, :id)}", "q=2"] ++
            placement_part(opts[:placement])
      end

    command(Enum.join(control, ","))
  end

  defp payload(raster, opts) do
    raster
    |> Raster.to_rgba_binary()
    |> deflate(opts[:compress])
    |> Base.encode64()
    |> chunk(@chunk_size)
  end

  defp deflate(binary, true), do: Deflate.compress(binary)
  defp deflate(binary, level) when is_integer(level), do: Deflate.compress(binary, level)
  defp deflate(binary, _off), do: binary

  defp compression(opts), do: if(opts[:compress], do: ",o=z", else: "")

  defp emit([only], control) do
    IO.iodata_to_binary(sequence(control <> ",m=0", only))
  end

  defp emit([first | rest], control) do
    IO.iodata_to_binary([sequence(control <> ",m=1", first) | continuations(rest)])
  end

  defp continuations([last]), do: [sequence("q=2,m=0", last)]
  defp continuations([part | rest]), do: [sequence("q=2,m=1", part) | continuations(rest)]

  defp fit_control(nil), do: ""
  defp fit_control({cols, rows}), do: ",c=#{cols},r=#{rows}"

  defp placement_part(nil), do: []
  defp placement_part(placement), do: ["p=#{placement}"]

  defp z_part(nil), do: []
  defp z_part(z), do: ["z=#{z}"]

  defp offset_part(nil, nil), do: []
  defp offset_part(x, y), do: ["X=#{x || 0}", "Y=#{y || 0}"]

  defp source_part(nil), do: []

  defp source_part({x, y, width, height}),
    do: [
      "x=" <> Integer.to_string(x),
      "y=" <> Integer.to_string(y),
      "w=" <> Integer.to_string(width),
      "h=" <> Integer.to_string(height)
    ]

  defp fit_part(nil), do: []
  defp fit_part({cols, rows}), do: ["c=#{cols}", "r=#{rows}"]

  defp command(control), do: "\e_G" <> control <> "\e\\"

  defp sequence(control, payload), do: ["\e_G", control, ";", payload, "\e\\"]

  defp chunk(binary, size) do
    case binary do
      <<part::binary-size(size), rest::binary>> when byte_size(rest) > 0 ->
        [part | chunk(rest, size)]

      other ->
        [other]
    end
  end
end
