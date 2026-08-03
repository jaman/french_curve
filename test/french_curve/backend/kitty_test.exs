defmodule FrenchCurve.Backend.KittyTest do
  use ExUnit.Case, async: true

  alias FrenchCurve.Backend.Kitty
  alias FrenchCurve.Raster

  defp payload_bytes(out) do
    [_control, rest] = String.split(out, ";", parts: 2)
    rest |> String.replace_trailing("\e\\", "") |> Base.decode64!()
  end

  test "emits a transmit-and-display RGBA sequence" do
    raster =
      Raster.new(2, 2, background: {0, 0, 0, 255})
      |> Raster.put_pixel(0, 0, {255, 0, 0, 255})

    out = Kitty.render(raster)

    assert String.starts_with?(out, "\e_G")
    assert String.ends_with?(out, "\e\\")
    assert out =~ "a=T"
    assert out =~ "f=32"
    assert out =~ "s=2,v=2"
  end

  test "carries the raw RGBA buffer row-major" do
    raster =
      Raster.new(2, 1, background: {0, 0, 0, 255})
      |> Raster.put_pixel(0, 0, {255, 0, 0, 255})
      |> Raster.put_pixel(1, 0, {0, 255, 0, 255})

    assert payload_bytes(Kitty.render(raster)) == <<255, 0, 0, 255, 0, 255, 0, 255>>
  end

  test "chunks large payloads with m=1 continuations and a final m=0" do
    raster = Raster.new(64, 64, background: {1, 2, 3, 255})
    out = Kitty.render(raster)

    assert length(String.split(out, "\e_G")) - 1 > 1
    assert out =~ "m=1"
    assert out =~ "m=0"
  end

  test "asks every chunk to stay quiet, so no chunk is answered on stdin" do
    raster = Raster.new(64, 64, background: {1, 2, 3, 255})

    chunks =
      Kitty.transmit(raster, 1)
      |> String.split("\e_G", trim: true)

    assert length(chunks) > 1
    assert Enum.all?(chunks, &String.contains?(&1, "q=2"))
  end

  test "fit: {cols, rows} scales the image into a cell box" do
    out = Kitty.render(Raster.new(8, 8), fit: {12, 6})
    assert out =~ "c=12,r=6"
  end

  test "omits cell placement when no fit is requested" do
    refute Kitty.render(Raster.new(8, 8)) =~ "c="
  end

  describe "drawing where the terminal has no placements" do
    test "the caret can be left where it was, so drawing low down does not scroll" do
      assert Kitty.render(Raster.new(8, 8), cursor: :keep) =~ "C=1"
      refute Kitty.render(Raster.new(8, 8)) =~ "C=1"
    end

    test "replies can be suppressed, so a repeated draw does not answer back as input" do
      assert Kitty.render(Raster.new(8, 8), quiet: true) =~ "q=2"
      refute Kitty.render(Raster.new(8, 8)) =~ "q=2"
    end

    test "it transmits and displays in one command rather than storing under an id" do
      out = Kitty.render(Raster.new(8, 8), cursor: :keep, quiet: true, fit: {10, 4})

      assert out =~ "a=T", "one command that both sends and shows"
      refute out =~ "a=t,", "nothing is stored under an id"
      refute out =~ "i=", "and so nothing names an id"
    end
  end

  describe "compression" do
    defp all_payload_bytes(out) do
      out
      |> String.split("\e_G", trim: true)
      |> Enum.map_join(fn part ->
        case String.split(part, ";", parts: 2) do
          [_control, rest] -> String.replace_trailing(rest, "\e\\", "")
          [_control_only] -> ""
        end
      end)
      |> Base.decode64!()
    end

    test "is off unless asked for, and then says so with o=z" do
      raster = Raster.new(4, 4, background: {9, 9, 9, 255})

      refute Kitty.render(raster) =~ "o=z"
      assert Kitty.render(raster, compress: true) =~ "o=z"
      refute Kitty.transmit(raster, 1) =~ "o=z"
      assert Kitty.transmit(raster, 1, compress: true) =~ "o=z"
    end

    test "the compressed payload inflates back to exactly the same pixels" do
      raster =
        Raster.new(8, 4, background: {10, 20, 30, 255})
        |> Raster.put_pixel(3, 2, {255, 0, 0, 255})

      inflated =
        raster
        |> Kitty.render(compress: true)
        |> all_payload_bytes()
        |> :zlib.uncompress()

      assert inflated == Raster.to_rgba_binary(raster)
      assert inflated == all_payload_bytes(Kitty.render(raster))
    end

    test "shrinks drawn images by orders of magnitude" do
      raster = Raster.new(160, 96, background: {12, 14, 20, 255})

      plain = byte_size(Kitty.render(raster))
      compressed = byte_size(Kitty.render(raster, compress: true))

      assert compressed * 50 < plain
    end

    test "a compressed image needs far fewer chunks, and still terminates correctly" do
      raster = Raster.new(160, 96, background: {12, 14, 20, 255})

      plain_chunks = length(String.split(Kitty.render(raster), "\e_G")) - 1
      compressed_chunks = length(String.split(Kitty.render(raster, compress: true), "\e_G")) - 1

      assert plain_chunks > 10
      assert compressed_chunks < plain_chunks
      assert Kitty.render(raster, compress: true) =~ "m=0"
    end

    test "the control data is only on the first chunk of a multi-chunk transmit" do
      out = Kitty.render(Raster.new(64, 64, background: {1, 2, 3, 255}))
      [first | rest] = String.split(out, "\e_G", trim: true)

      assert first =~ "a=T"
      assert first =~ "s=64,v=64"
      refute Enum.any?(rest, &(&1 =~ "a=T"))
      refute Enum.any?(rest, &(&1 =~ "f=32"))
    end
  end

  describe "sprite primitives" do
    test "transmit/2 stores an image under an id without displaying" do
      out = Kitty.transmit(Raster.new(2, 2), 7)
      assert String.starts_with?(out, "\e_G")
      assert String.ends_with?(out, "\e\\")
      assert out =~ "a=t,i=7"
      assert out =~ "f=32"
    end

    test "place/2 references an image with z-index and a cell box" do
      out = Kitty.place(7, z: 3, fit: {4, 2}, placement: 9)
      assert out =~ "a=p"
      assert out =~ "i=7"
      assert out =~ "z=3"
      assert out =~ "c=4,r=2"
      assert out =~ "p=9"
      assert out =~ "C=1"
    end

    test "delete/1 removes a placement by id" do
      out = Kitty.delete(id: 7, placement: 9)
      assert out =~ "a=d"
      assert out =~ "i=7"
      assert out =~ "p=9"
    end
  end
end
