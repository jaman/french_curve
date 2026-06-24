defmodule SpritesDemo do
  alias FrenchCurve.{Draw, Raster, Sprite}
  alias FrenchCurve.Sprite.Registry

  @cols 8
  @rows 5
  @tile_cells {4, 2}
  @tile_px {40, 40}
  @floor_color {34, 36, 48}

  @trees [{0, 1}, {1, 4}, {2, 2}, {3, 6}, {4, 0}, {1, 7}, {3, 1}]
  @player {2, 3}

  def run([]), do: render(:kitty)
  def run([protocol]), do: render(String.to_atom(protocol))

  defp render(protocol) do
    IO.write("\e[2J\e[H")
    sprites = build_sprites()

    {_registry, uploads} =
      Enum.reduce(sprites, {Registry.new(), ""}, fn {_key, sprite}, {registry, acc} ->
        {registry, bytes} = Registry.ensure(registry, sprite, protocol)
        {registry, acc <> bytes}
      end)

    IO.write(uploads)
    Enum.each(scene(), fn {row, col, key} -> draw(sprites[key], key, protocol, row, col) end)
    IO.write("\e[#{@rows * 2 + 2};1H")
  end

  defp scene do
    floor = for r <- 0..(@rows - 1), c <- 0..(@cols - 1), do: {r, c, :floor}
    trees = Enum.map(@trees, fn {r, c} -> {r, c, :tree} end)
    {pr, pc} = @player
    floor ++ trees ++ [{pr, pc, :player}]
  end

  defp draw(sprite, key, protocol, grid_row, grid_col) do
    {tile_cols, tile_rows} = @tile_cells
    line = grid_row * tile_rows + 1
    column = grid_col * tile_cols + 1
    placement = grid_row * @cols + grid_col + 1

    opts = [fit: @tile_cells, placement: placement, z: layer(key)] ++ backdrop(protocol)

    IO.write("\e[#{line};#{column}H")
    IO.write(Sprite.place(sprite, protocol, opts))
  end

  defp backdrop(:sixel), do: [background: @floor_color]
  defp backdrop(_protocol), do: []

  defp layer(:floor), do: 0
  defp layer(:tree), do: 1
  defp layer(:player), do: 2

  defp build_sprites do
    %{floor: floor_sprite(), tree: tree_sprite(), player: player_sprite()}
  end

  defp floor_sprite do
    {w, h} = @tile_px

    Raster.new(w, h, background: {34, 36, 48, 255})
    |> Draw.rect({0, 0}, {w - 1, h - 1}, {46, 50, 66, 255})
    |> Sprite.new(id: 1)
  end

  defp tree_sprite do
    {w, h} = @tile_px
    cx = div(w, 2)
    cy = div(h, 2)

    Raster.new(w, h)
    |> Draw.fill_rect({cx - 3, cy}, {cx + 2, h - 1}, {110, 72, 40, 255})
    |> Draw.fill_circle({cx - 7, cy + 2}, 9, {70, 185, 95, 255})
    |> Draw.fill_circle({cx + 7, cy + 2}, 9, {70, 185, 95, 255})
    |> Draw.fill_circle({cx, cy - 4}, 13, {60, 170, 80, 255})
    |> Sprite.new(id: 2)
  end

  defp player_sprite do
    {w, h} = @tile_px
    cx = div(w, 2)
    cy = div(h, 2)

    Raster.new(w, h)
    |> Draw.fill_circle({cx, cy}, 15, {220, 80, 80, 255})
    |> Draw.fill_circle({cx - 5, cy - 3}, 3, {255, 255, 255, 255})
    |> Draw.fill_circle({cx + 5, cy - 3}, 3, {255, 255, 255, 255})
    |> Draw.fill_circle({cx - 5, cy - 3}, 1, {20, 20, 20, 255})
    |> Draw.fill_circle({cx + 5, cy - 3}, 1, {20, 20, 20, 255})
    |> Sprite.new(id: 3)
  end
end

SpritesDemo.run(System.argv())
