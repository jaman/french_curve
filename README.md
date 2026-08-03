# FrenchCurve

Pure-Elixir terminal graphics for **generating** visualizations — charts, graphs,
lines — and emitting them through whichever image protocol the terminal supports.
No native dependencies, no image decoding (you draw the pixels), no supervision tree.

[![Hex.pm](https://img.shields.io/hexpm/v/french_curve.svg)](https://hex.pm/packages/french_curve)
[![Docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/french_curve)

## Installation

```elixir
def deps do
  [
    {:french_curve, "~> 0.1"}
  ]
end
```

Nothing to start and nothing to configure — every module is a pure function over values.

## Pipeline

```
data ──▶ Curve (smoothing) ──▶ Draw ──▶ Raster (RGBA buffer) ──▶ Backend ──▶ terminal
```

A single `Raster` is the buffer every backend consumes; the backends only differ in
how they serialize it.

## Backends

| Backend | Output | Terminals |
|---|---|---|
| `:braille` | Unicode 2×4 dot cells (text) | Every terminal (incl. Ghostty, Alacritty, tmux, ssh) |
| `:kitty` | Kitty graphics protocol, raw RGBA (`f=32`) | Kitty, Ghostty, WezTerm, Konsole |
| `:sixel` | Sixel (palette-based, RLE) | iTerm2, WezTerm, foot, Konsole, xterm |
| `:iterm2` | iTerm2 inline image (PNG via `:zlib`) | iTerm2, WezTerm |

`:braille` returns cell rows (`[[{grapheme, rgb_or_nil}]]`); the pixel backends
return an escape-sequence string.

## Usage

```elixir
raster =
  FrenchCurve.Raster.new(120, 48)
  |> FrenchCurve.Draw.polyline([{0, 47}, {40, 10}, {80, 30}, {119, 0}], {0, 200, 255, 255})

# explicit protocol
FrenchCurve.render(raster, :kitty, [])

# auto-detect from the environment
FrenchCurve.render(raster)
```

### From data

```elixir
[3, 1, 4, 1, 5, 9, 2, 6]
|> FrenchCurve.Chart.line(width: 120, height: 48, color: {0, 200, 255, 255}, smooth: true)
|> FrenchCurve.render(:braille)
|> FrenchCurve.Backend.Braille.to_text()
|> Enum.each(&IO.puts/1)
```

## Try it

`examples/render_demo.exs` draws smoothed sine/cosine curves and emits them through
a chosen backend, straight to your terminal:

```bash
mix run examples/render_demo.exs           # line chart, every backend, labelled
mix run examples/render_demo.exs auto       # detect this terminal and render that one
mix run examples/render_demo.exs kitty      # kitty | sixel | iterm2 | braille

mix run examples/area_demo.exs              # filled area chart, every backend
mix run examples/area_demo.exs sixel        # or a single backend

mix run examples/animated_area.exs          # live scrolling braille area chart
mix run examples/animated_area.exs sixel     # animate via a pixel backend
mix run examples/animated_area.exs sixel 40  # pixel backend, N frames then stop
```

`to_terminal/3` returns a printable binary for any backend (braille cells are
converted to ANSI; pixel backends pass through), so swapping backends needs no
other change.

`braille` renders in any terminal; `kitty`/`sixel`/`iterm2` only display where the
terminal supports that protocol (elsewhere you'll see raw escape bytes).

## Redrawing a region

A picture drawn once is `to_terminal/3`. A region drawn over and over — a meter, a scope,
anything animated — is `FrenchCurve.frame/3`, which returns `{paint, clear, place}`:

```elixir
{paint, clear, place} = FrenchCurve.frame(raster, :meter, fit: {40, 8})

IO.write(paint)              # draw it
IO.write(place || paint)     # draw it again without resending the pixels
IO.write(clear)              # take it off
```

`id` (`:meter` above) names the region across frames — any term, hashed to a protocol image
id — so each frame replaces the last instead of piling up. `place` is `nil` where the
protocol has no stored image, and redrawing then means sending `paint` again. `frame/3`
returns `nil` outright for `:braille`, which is the caller's cue to draw text.

Two things it settles that a caller cannot see from `Capability.detect/0`. First, a kitty
terminal may or may not implement stored images and placements, and one that does not draws
*nothing* when sent a store followed by a placement — `frame/3` asks `Capability.placements?/0`
and picks the dialect. Second, the image is always **named**, so `clear` really removes it: a
kitty image is an overlay rather than cells, so text drawn over it does not rub it out and
leaving the alternate screen does not discard it. An unnamed one cannot be taken off at all,
and is still on the screen after the program has exited.

Positioning stays the host's job either way: `frame/3` draws at the cursor, so put the
cursor where you want the region first. `examples/animated_area.exs` does exactly this —
cursor-home, then `paint` — across all four protocols.

## Embedding in a host application (a sub-region)

FrenchCurve never owns the screen or the cursor. A host (e.g. a TUI framework) decides
*where* a chart goes — a cell region like full-width-from-row-N, `{r1c1..r3c5}`, a flex
slot — positions the cursor there, and writes the bytes FrenchCurve returns. FrenchCurve's
only spatial responsibility is **sizing the output to fit a cell box**.

Sizing is hybrid by protocol:

| Protocol | How it fits a `{cols, rows}` cell box |
|---|---|
| `:kitty` | pass `fit: {cols, rows}` — the terminal scales the image; no cell-pixel size needed |
| `:iterm2` | pass `fit: {cols, rows}` — sized in cells natively; no cell-pixel size needed |
| `:sixel` | render the raster at `cols*cell_w × rows*cell_h` pixels (needs cell-pixel size) |
| `:braille` | render the raster at `cols*2 × rows*4` (braille's fixed cell, no detection) |

```elixir
# kitty / iterm2 — terminal scales to the cell box:
raster = FrenchCurve.Chart.line(data, width: 400, height: 200, smooth: true)
FrenchCurve.render(raster, :kitty, fit: {cols, rows})

# sixel — size the raster to the region; detect cell-pixel size if the host can:
cell_px =
  case FrenchCurve.Geometry.detect_cell_size(&host_query_tty/1) do
    {:ok, px} -> px
    :error -> :unknown
  end

{w, h} = FrenchCurve.Geometry.pixels_for_cells({cols, rows}, cell_px)
data |> FrenchCurve.Chart.line(width: w, height: h) |> FrenchCurve.render(:sixel, [])
```

**Cell-pixel detection stays in the host.** FrenchCurve gives you the query bytes
(`Geometry.cell_size_query/0`) and the parser (`Geometry.parse_cell_size/1`), or a one-call
`Geometry.detect_cell_size/1` that takes *your* IO function (`fn query -> write+read tty end`).
The host owns the tty, raw mode, and timeout; FrenchCurve never reads or writes it.

## Sprites (tiles, tokens, game grids)

A `Sprite` is a `Raster` with a stable, content-addressed id. The point is **one
definition, many placements** — author a tile once, stamp it across a grid cheaply.
This mirrors how Elixir already shares the underlying pixel binary, and on kitty it
mirrors the protocol too (transmit once, place many by reference, with z-index layers).

```elixir
tree = FrenchCurve.Sprite.new(tree_raster, id: 2)

# upload once (kitty stores it; other backends return "" — nothing to pre-upload)
{registry, bytes} = FrenchCurve.Sprite.Registry.ensure(FrenchCurve.Sprite.Registry.new(), tree, :kitty)
IO.write(bytes)

# the host positions the cursor, then places — as many times as you like
IO.write("\e[#{line};#{col}H")
IO.write(FrenchCurve.Sprite.place(tree, :kitty, fit: {4, 2}, z: 1, placement: 17))
```

| Backend | `place/3` realizes a placement as | `upload`/`delete` |
|---|---|---|
| `:kitty` | a reference to the uploaded image (`a=p`, with `z=` layering, `c=/r=` cell box) — cheapest, flat cost per placement | `transmit` once / `delete` a placement |
| `:sixel` / `:iterm2` | re-emit the sprite's pixels (cost grows with placement count) | no-op |
| `:braille` | rasterize to colored cells (low fidelity fallback) | no-op |

Position and z-ordering for non-kitty backends are the host's job (cursor placement +
emission order = painter's algorithm). kitty's `z=` does true layering.

**Sixel has no alpha.** Transparent pixels rely on `P2=1`, which many decoders (iTerm2
included) ignore — they flood unset pixels with the last palette color. For sixel,
composite onto a solid backdrop instead: `place(sprite, :sixel, background: {r, g, b})`
fills transparent pixels with that color, so a sprite reads correctly over a known
background. kitty and iterm2 use true RGBA and keep real transparency with no backdrop.

```bash
mix run examples/sprites_demo.exs kitty   # a floor/tree/player scene; kitty | sixel | iterm2
```

### Loading sprites from a catalog

`Raster.from_rgba/4` is the pure inverse of `to_rgba_binary/1` — load authored art with
no image decoder. Store a catalog as raw RGBA + dims (optionally zlib-compressed for
download; `:zlib` is built into OTP), then inflate and load locally:

```elixir
{w, h, packed} = fetch_from_catalog("tree")          # your transport
rgba = :zlib.uncompress(packed)                        # if you compressed it
tree = w |> Raster.from_rgba(h, rgba) |> Sprite.new()
```


## Compression (kitty)

`compress: true` deflates the pixels before base64 and tells the terminal with `o=z`:

```elixir
FrenchCurve.render(raster, :kitty, compress: true, fit: {cols, rows})
FrenchCurve.Backend.Kitty.transmit(raster, id, compress: true)
FrenchCurve.Sprite.upload(sprite, :kitty, compress: true)
```

Off by default: the protocol's compression is optional, so a partial implementation may not
have it. Turn it on when you know what you are drawing to.

It matters because of what image data usually *is* here. Anything drawn rather than
photographed — a chart, a tilemap, a sprite sheet — is enormously repetitive, and that is the
case zlib is best at. Measured on a 640×384 tilemap frame:

| | payload | deflate |
|---|---|---|
| uncompressed | 1,310,720 B | — |
| `compress: true` | 4,160 B | ~1 ms |

315× smaller for about a millisecond. The saving is not only bandwidth: the payload is chunked
into 4 KiB pieces that each carry their own escape sequence, so it is also 315× fewer chunks to
build and for the terminal to reassemble. A photograph would compress far less; the ratio
follows the picture, not the protocol.

## Capability detection

`FrenchCurve.Capability.detect/0` picks a protocol from `KITTY_WINDOW_ID`, `TERM`,
`TERM_PROGRAM`, `WEZTERM_PANE`, `LC_TERMINAL` and `KONSOLE_VERSION`, preferring
`kitty > iterm2 > sixel > braille`, and caches the result in `:persistent_term` for the
life of the VM. `detect/1` takes an environment map instead and does not cache — that is
the one to use for an ssh or multiplexer session, whose environment is not the host's.
Pass an explicit `protocol:` to override either.

iTerm is deliberately **not** detected as `:kitty` even though it understands kitty's
transmit-and-display: a kitty image is an overlay rather than cells, and removing one takes
an explicit delete addressed to its id, which iTerm does not implement. Its own inline-image
protocol scrolls and disappears with the screen, like text.

### Asking the terminal instead

Environment variables are a guess. `Capability.probe/0` returns the bytes that ask the
terminal directly (XTVERSION plus primary device attributes); write them, read until
`probe_complete?/1` is true or your timeout expires, then hand the replies to
`from_probe/1`:

```elixir
replies = read_until(&FrenchCurve.Capability.probe_complete?/1, IO.write(FrenchCurve.Capability.probe()))

protocol = FrenchCurve.Capability.from_probe(replies) || FrenchCurve.Capability.detect()
```

`from_probe/1` returns `nil` when the replies name nothing usable, and a terminal that
answers neither query says nothing at all — so the caller owns the timeout, exactly as it
owns the tty.

`Capability.placements?/0` is a separate question from the protocol: a terminal can speak
kitty's transmit-and-display without keeping images under an id, and sending such a
terminal a store followed by a placement draws nothing at all. `FrenchCurve.frame/3` asks
this for you.
