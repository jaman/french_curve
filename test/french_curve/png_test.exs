defmodule FrenchCurve.PngTest do
  use ExUnit.Case, async: true

  alias FrenchCurve.Png

  @signature <<137, 80, 78, 71, 13, 10, 26, 10>>

  test "encodes a 1x1 RGBA pixel into a valid PNG structure" do
    png = Png.encode(1, 1, <<255, 0, 0, 255>>)

    <<@signature, rest::binary>> = png
    <<13::32, "IHDR", ihdr::binary-size(13), _ihdr_crc::32, rest2::binary>> = rest
    assert ihdr == <<1::32, 1::32, 8, 6, 0, 0, 0>>

    <<idat_len::32, "IDAT", idat::binary-size(idat_len), _idat_crc::32, _rest3::binary>> = rest2
    assert :zlib.uncompress(idat) == <<0, 255, 0, 0, 255>>
  end

  test "prefixes every scanline with a filter byte" do
    rgba = <<1, 2, 3, 255, 4, 5, 6, 255>>
    png = Png.encode(1, 2, rgba)

    <<@signature, _ihdr_len::32, "IHDR", _ihdr::binary-size(13), _crc::32, rest::binary>> = png
    <<idat_len::32, "IDAT", idat::binary-size(idat_len), _crc2::32, _::binary>> = rest

    assert :zlib.uncompress(idat) == <<0, 1, 2, 3, 255, 0, 4, 5, 6, 255>>
  end

  test "ends with an IEND chunk" do
    png = Png.encode(1, 1, <<0, 0, 0, 0>>)
    assert String.ends_with?(png, "IEND" <> <<:erlang.crc32("IEND")::32>>)
  end
end
