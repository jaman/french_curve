# Changelog

## [0.2.1]

### Added

- `FrenchCurve.Raster.fill_spans/3`: fills horizontal runs straight into the dense buffer in one splice. `put_pixels/3` writes many pixels in one map merge.
- `FrenchCurve.Draw.fill_columns/3` fills vertical columns as row spans; `FrenchCurve.Draw.line_points/2` returns a line's pixels.

### Changed

- A raster is a dense base buffer with a map of single-pixel writes over it. `put_pixel/4` no longer expands a buffer-backed raster into a map, `finalize/1` folds the map into the buffer, and `to_rgba_binary/1` and `rows/1` splice instead of reading every pixel through `get_pixel/3`.
- `Draw` writes each shape in one raster update and `Chart.area/2` fills with spans. Output is byte-identical; a 480×192 area chart draws in about 4.6 ms (was 17 ms) and converts to RGBA in 0.3 ms (was 9.3 ms).

## [0.2.0]

### Breaking changes

- Compiling now runs `make` through `elixir_make` (`compilers: [:elixir_make | Mix.compilers()]`), so `make` and `erl` must be on `PATH` at build time; on Windows, `nmake` runs `Makefile.win`, which builds the cells NIF with `cl` when it is present. A C compiler and libdeflate stay optional: without a compiler `FrenchCurve.Backend.Cells` quantises in Elixir, and without libdeflate `FrenchCurve.Deflate` uses `:zlib`. Nothing to change in code; install `make` on build machines that lack it.
- When libdeflate is built, kitty payloads sent with `compress:` are different bytes from the `:zlib` output of 0.1.4. Terminals decode the same pixels; tests that compare exact escape-sequence bytes need new expected values.

### Added

- `FrenchCurve.Png.encode_indexed/4`: a palette PNG, a byte a pixel, for a buffer of at
  most 256 colours, else `{:error, :too_many_colours}`.
- `FrenchCurve.Backend.Kitty.encode/2` and `transmit_encoded/2`: a raster's pixels
  encoded once and stored under any id without encoding them again; `encode/2` takes
  `format: :png` (`f=100`), a palette PNG where the raster allows, else a truecolour one.
  `transmit/3` is unchanged.

- `:cells` protocol and `FrenchCurve.Backend.Cells`: draws a raster as block characters with a foreground and background colour per cell. Glyph sets via `set:` — `:half` (1×2), `:quad` (2×2), `:sextant` (2×3), `:braille` (2×4 dots), `:octant` (2×4). Options `:background` and `:alpha_threshold` (default `128`).
- `FrenchCurve.Backend.Cells.render/2`, `to_ansi/1`, `glyph/2`, `sets/0`, `subpixels/1`, `available?/0`, and `default_set/1`, which suggests a set from a protocol atom or an environment map (`:sextant` for iTerm2, `:octant` for kitty-protocol terminals, `:half` otherwise).
- Cell rendering uses a native helper when a C compiler is available at build time; `native: false` on `FrenchCurve.Backend.Cells.render/2` forces the Elixir path.
- `FrenchCurve.render/3` and `FrenchCurve.to_terminal/3` accept `:cells`; `to_terminal/3` returns the ANSI string. `FrenchCurve.frame/3` returns `nil` for `:cells`, as for `:braille`.
- `FrenchCurve.Capability.backend(:cells)` returns `FrenchCurve.Backend.Cells`. `:cells` is never returned by `detect/0,1`; name it explicitly.
- `FrenchCurve.Deflate.compress/1,2`: zlib-format compression through libdeflate (levels `1..12`) when the NIF is built, `:zlib` (levels clamped to `1..9`) otherwise. `FrenchCurve.Deflate.available?/0` reports which is in use.
- Kitty `:compress` option on `FrenchCurve.Backend.Kitty.render/2` and `transmit/3` takes an integer compression level as well as `true`.
- `FrenchCurve.Capability.iterm2?/1`: whether an environment map describes an iTerm2 session, locally or over ssh.
- `FRENCH_CURVE_ITERM2=kitty` makes `FrenchCurve.Capability.detect/1` return `:kitty` for iTerm2; `inline` or unset returns `:iterm2`.

### Changed

- The compiled native code is built into and loaded from
  `priv/native/<system architecture>` (`FrenchCurve.Native`) instead of `priv/`, so builds
  for macOS and Linux in one checkout no longer overwrite each other. `mix.exs` passes the
  folder to `make` as `PRIV_DIR`.

- `FrenchCurve.Raster.to_rgba_binary/1` of a raster with no pixels set returns its
  background repeated.
- `FrenchCurve.Capability.placements?/1` is `false` for iTerm2, including when it is detected as `:kitty`, so `FrenchCurve.frame/3` retransmits each frame there instead of placing a stored image.
- Packaging: `Makefile`, `Makefile.win`, `c_src` and `CHANGELOG.md` are in the Hex package files, and the package description reads "Terminal graphics for Elixir".

## [0.1.4]

### Added

- `FrenchCurve.Draw.fill_polygon/3`: fills a closed polygon with fractional corner points, even-odd rule, outline included. Fewer than three points draw as a polyline.
- `FrenchCurve.Raster.crop/3`: returns a `{width, height}` rectangle of a raster starting at `{x, y}`; the rectangle must lie inside the raster.
- `FrenchCurve.Backend.Kitty.place/2` options `:x_offset` and `:y_offset` (pixel shift inside the cursor cell) and `:source` (`{x, y, width, height}`, the part of the stored image to show).
- `FrenchCurve.Backend.Kitty.delete/1` option `:z`: removes every placement at that z-index, of any image, keeping the images stored. `:id` is required only when `:z` is not given.

### Changed

- `FrenchCurve.Png.encode/3` deflates at the fastest level.

## [0.1.3]

### Changed

- Development dependency `plumb` raised to `~> 0.2`. No library code changes.

## [0.1.2]

### Added

- Hex package metadata, MIT `LICENSE`, and ExDoc configuration with modules grouped as Drawing, Backends, Sprites, Terminal and Encoding.
- `@doc` for `FrenchCurve.Capability.placements?/1`.

## [0.1.1]

### Added

- `FrenchCurve.Raster`: fixed-size RGBA buffer with `new/3`, `dimensions/1`, `in_bounds?/3`, `put_pixel/4`, `get_pixel/3`, `rows/1`, `to_rgba_binary/1`, `finalize/1`, `from_rgba/4`.
- `FrenchCurve.Draw`: `line/4`, `polyline/3`, `rect/4`, `fill_rect/4`, `circle/4`, `fill_circle/4`.
- `FrenchCurve.Chart.line/2` and `area/2`: plot a list of numbers across a raster, optionally smoothed.
- `FrenchCurve.Curve.catmull_rom/2` and `to_pixels/1`.
- Backends `FrenchCurve.Backend.Kitty`, `Sixel`, `Iterm2` and `Braille`.
- `FrenchCurve.render/2,3` returns each backend's native output; `FrenchCurve.to_terminal/3` returns a binary for every protocol.
- `FrenchCurve.frame/3`: returns `{paint, clear, place}` sequences for a region drawn repeatedly, picking between kitty transmit-and-place and transmit-and-display. `FrenchCurve.image_id/1` maps any term to a kitty image id.
- `FrenchCurve.Backend.Kitty.transmit/3`, `place/2` and `delete/1`; `render/2` options `:fit`, `:compress`, `:cursor`, `:quiet`, `:id`. All `transmit/3`, `place/2` and `delete/1` chunks carry `q=2`.
- `FrenchCurve.Capability.detect/0,1` reads `KITTY_WINDOW_ID`, `TERM`, `TERM_PROGRAM`, `WEZTERM_PANE`, `LC_TERMINAL` and `KONSOLE_VERSION`; iTerm2 is detected as `:iterm2`; empty variables count as unset. `detect/0` is cached in `:persistent_term`.
- `FrenchCurve.Capability.probe/0`, `probe_complete?/1` and `from_probe/1`: detect the protocol from the terminal's replies to a query sequence.
- `FrenchCurve.Capability.placements?/0,1` and `backend/1`.
- `FrenchCurve.Geometry`: `cell_size_query/0`, `parse_cell_size/1`, `detect_cell_size/1`, `default_cell_px/0`, `braille_cell_px/0` and `pixels_for_cells/2`.
- `FrenchCurve.Png.encode/3`.
- `FrenchCurve.Sprite` (`new/2`, `upload/3`, `place/3`, `delete/3`) and `FrenchCurve.Sprite.Registry` (`new/0`, `ensure/3`). `upload/3` takes kitty transmit options such as `:compress`.
