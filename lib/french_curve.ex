defmodule FrenchCurve do
  @moduledoc """
  Draws pixel rasters to a terminal over whichever graphics protocol it supports.

  A `FrenchCurve.Raster` is built with `FrenchCurve.Draw` or `FrenchCurve.Chart`, then
  handed to one of four backends: `:kitty`, `:sixel`, `:iterm2` or `:braille`.
  `FrenchCurve.Capability.detect/0` picks one from the environment when none is named.

      raster =
        FrenchCurve.Raster.new(64, 32)
        |> FrenchCurve.Draw.circle({32, 16}, 12, {255, 0, 0, 255})

      IO.write(FrenchCurve.to_terminal(raster, :kitty))

  `render/2` and `render/3` return each backend's native form, which differs by protocol:
  the three pixel backends return an escape-sequence binary, `:braille` returns cell rows.
  `to_terminal/3` returns a binary for every protocol and is what you write to the device.

  For a region that is drawn over and over — a meter, a scope, anything animated — use
  `frame/3` rather than building the sequence yourself. It picks between the two kitty
  dialects, which is not something a caller can tell from `FrenchCurve.Capability.detect/0`
  alone.
  """

  alias FrenchCurve.Backend.{Braille, Kitty}
  alias FrenchCurve.{Capability, Raster}

  @typedoc """
  What it takes to draw a region and draw it again: `{paint, clear, place}`.

  `paint` puts the picture on the screen and `clear` takes it off. `place` draws the picture
  already sent without sending it again, and is `nil` where the protocol has no such thing —
  redrawing then means sending `paint` once more.
  """
  @type frame :: {binary, binary, binary | nil}

  @doc """
  The sequences for drawing `raster` into a cell box, and for drawing it again.

  Use this rather than assembling a frame from `FrenchCurve.Backend.Kitty`'s pieces. The kitty
  protocol can store an image under an id and place it repeatedly, which is the cheap way to
  animate — but not every terminal that speaks kitty implements that part, and one that does
  not draws nothing at all when sent a store and then a placement.
  `FrenchCurve.Capability.placements?/0` is the question, and this function asks it.

  Either way the image is **named** and `clear` really removes it. That matters more than it
  looks: a kitty image is an overlay rather than cells, so text drawn over it does not rub it
  out and leaving the alternate screen does not discard it. An unnamed one cannot be taken off
  at all, and is still on the screen after the program has exited.

  `id` names the region across frames — any term; the same one must come back each time so the
  picture replaces itself rather than piling up. `nil` for a terminal with no pixels at all,
  which is the caller's cue to draw text instead.

  ## Options

    * `:fit` — `{cols, rows}`, the cell box to draw into. Omitted sizes from the pixels
    * `:compress` — deflate the payload where the protocol allows, default `true`
    * `:protocol` — force one instead of detecting. `:placements` forces the kitty dialect

  ## Examples

      iex> raster = FrenchCurve.Raster.new(8, 8)
      iex> {paint, clear, place} =
      ...>   FrenchCurve.frame(raster, :meter, fit: {10, 2}, protocol: :kitty, placements: true)
      iex> {paint =~ "a=t,", paint =~ "a=p", clear =~ "a=d", is_binary(place)}
      {true, true, true, true}

      iex> raster = FrenchCurve.Raster.new(8, 8)
      iex> {paint, clear, place} =
      ...>   FrenchCurve.frame(raster, :meter, fit: {10, 2}, protocol: :kitty, placements: false)
      iex> {paint =~ "a=T", paint =~ "a=p", clear =~ "a=d", place}
      {true, false, true, nil}

      iex> FrenchCurve.frame(FrenchCurve.Raster.new(8, 8), :meter, protocol: :braille)
      nil
  """
  @spec frame(Raster.t(), term, keyword) :: frame | nil
  def frame(%Raster{} = raster, id, opts \\ []) do
    case Keyword.get(opts, :protocol) || Capability.detect() do
      :braille -> nil
      :kitty -> kitty_frame(raster, id, opts)
      protocol -> {to_terminal(raster, protocol, fit: opts[:fit]), "", nil}
    end
  end

  defp kitty_frame(raster, id, opts) do
    fit = opts[:fit]
    compress? = Keyword.get(opts, :compress, true)

    image = image_id(id)

    if Keyword.get_lazy(opts, :placements, &Capability.placements?/0) do
      clear = Kitty.delete(id: image, placement: 1)
      place = Kitty.place(image, placement: 1, fit: fit)

      {clear <> Kitty.transmit(raster, image, compress: compress?) <> place, clear, place}
    else
      clear = Kitty.delete(id: image)

      paint =
        Kitty.render(raster,
          id: image,
          fit: fit,
          compress: compress?,
          cursor: :keep,
          quiet: true
        )

      {clear <> paint, clear, nil}
    end
  end

  @doc """
  The kitty image id for `id`, a positive integer inside the protocol's range.

  Any term becomes the same number every time, so a caller can name its regions however it
  likes and still have each one replace itself.

      iex> FrenchCurve.image_id({:roll, 3}) == FrenchCurve.image_id({:roll, 3})
      true
      iex> FrenchCurve.image_id(:anything) > 0
      true
  """
  @spec image_id(term) :: pos_integer
  def image_id(id), do: :erlang.phash2(id, 4_000_000_000) + 1

  @doc """
  Renders `raster` with the protocol given in `opts`, or with the detected one.

  Options are passed through to the backend, plus:

    * `:protocol` — `:kitty`, `:sixel`, `:iterm2` or `:braille`. Defaults to
      `FrenchCurve.Capability.detect/0`.

  Returns a binary for the pixel protocols and `[[FrenchCurve.Backend.Braille.cell()]]`
  for `:braille`.
  """
  @spec render(Raster.t(), keyword) :: term
  def render(%Raster{} = raster, opts \\ []) do
    protocol = Keyword.get(opts, :protocol) || Capability.detect()
    render(raster, protocol, opts)
  end

  @doc """
  Renders `raster` with `protocol`, delegating to that backend's `render/2`.

  `protocol` must be one of `:kitty`, `:sixel`, `:iterm2` or `:braille`; any other atom
  raises `FunctionClauseError` from `FrenchCurve.Capability.backend/1`. `opts` are the
  options of the backend selected — see `FrenchCurve.Backend.Kitty.render/2`,
  `FrenchCurve.Backend.Sixel.render/2`, `FrenchCurve.Backend.Iterm2.render/2` and
  `FrenchCurve.Backend.Braille.render/2`.

  Returns a binary for the pixel protocols and cell rows for `:braille`.
  """
  @spec render(Raster.t(), atom, keyword) :: term
  def render(%Raster{} = raster, protocol, opts) when is_atom(protocol) do
    backend = Capability.backend(protocol)
    backend.render(raster, opts)
  end

  @doc """
  Renders `raster` with `protocol` as a binary ready to write to the terminal.

  Identical to `render/3` except that `:braille` cell rows are converted to a
  newline-separated ANSI string. `opts` are the selected backend's options.
  """
  @spec to_terminal(Raster.t(), atom, keyword) :: binary
  def to_terminal(raster, protocol, opts \\ [])

  def to_terminal(%Raster{} = raster, :braille, opts) do
    raster |> render(:braille, opts) |> Braille.to_ansi()
  end

  def to_terminal(%Raster{} = raster, protocol, opts) when is_atom(protocol) do
    render(raster, protocol, opts)
  end
end
