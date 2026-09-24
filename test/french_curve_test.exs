defmodule FrenchCurveTest do
  use ExUnit.Case, async: true

  alias FrenchCurve.Raster

  doctest FrenchCurve

  defp sample, do: Raster.put_pixel(Raster.new(2, 4), 0, 0, {255, 0, 0, 255})

  describe "frame/3" do
    defp frame(opts), do: FrenchCurve.frame(sample(), :region, opts)

    test "a terminal with placements stores the image and places it" do
      {paint, clear, place} = frame(protocol: :kitty, placements: true, fit: {8, 2})

      assert paint =~ "a=t,", "stored under an id"
      assert paint =~ "a=p", "then placed"
      assert clear =~ "a=d", "and deletable"
      assert place =~ "a=p", "with a placement to redraw it cheaply"
    end

    test "a terminal without them transmits and displays in one command" do
      {paint, clear, place} = frame(protocol: :kitty, placements: false, fit: {8, 2})

      assert paint =~ "a=T"
      refute paint =~ "a=t,", "storing would leave the terminal holding a picture it never shows"
      refute paint =~ "a=p", "and it does not understand a placement"
      assert place == nil, "so redrawing means sending the picture again"

      assert clear =~ "a=d", "but it must still be removable"
    end

    test "the one-shot image is named, so it can be taken off the screen again" do
      {paint, clear, _place} = frame(protocol: :kitty, placements: false)
      id = FrenchCurve.image_id(:region)

      assert paint =~ "i=#{id}", "an unnamed overlay could never be deleted"
      assert clear =~ "i=#{id}", "and the delete has to name the same one"
    end

    test "each frame deletes the one before it rather than stacking overlays" do
      {paint, clear, _place} = frame(protocol: :kitty, placements: false)

      assert String.starts_with?(paint, clear),
             "an overlay is not cells, so the old one has to go before the new one arrives"
    end

    test "two regions get two ids, so one does not delete the other" do
      {a, _, _} = FrenchCurve.frame(sample(), :one, protocol: :kitty, placements: false)
      {b, _, _} = FrenchCurve.frame(sample(), :two, protocol: :kitty, placements: false)

      assert a =~ "i=#{FrenchCurve.image_id(:one)}"
      assert b =~ "i=#{FrenchCurve.image_id(:two)}"
      refute FrenchCurve.image_id(:one) == FrenchCurve.image_id(:two)
    end

    test "the one-shot path keeps the caret and stays quiet" do
      {paint, _clear, _place} = frame(protocol: :kitty, placements: false)

      assert paint =~ "C=1", "or a picture low on the screen scrolls it"
      assert paint =~ "q=2", "or the replies arrive as keystrokes"
    end

    test "it asks the environment when not told" do
      detected = FrenchCurve.frame(sample(), :region, fit: {8, 2})

      case FrenchCurve.Capability.detect() do
        :braille -> assert detected == nil
        _pixels -> assert {_paint, _clear, _place} = detected, "got #{inspect(detected)}"
      end
    end

    test "the inline protocols are one sequence with nothing to place" do
      for protocol <- [:iterm2, :sixel] do
        {paint, clear, place} = frame(protocol: protocol, fit: {8, 2})

        assert byte_size(paint) > 0, "#{protocol} should draw something"
        assert clear == ""
        assert place == nil
      end
    end

    test "a terminal with no pixels at all is nothing to draw" do
      assert frame(protocol: :braille) == nil
    end

    test "the box asked for is the box drawn into" do
      {paint, _clear, _place} = frame(protocol: :kitty, placements: false, fit: {12, 6})

      assert paint =~ "c=12,r=6"
    end

    test "the same region keeps the same image id, a different one does not" do
      assert FrenchCurve.image_id({:roll, 1}) == FrenchCurve.image_id({:roll, 1})
      refute FrenchCurve.image_id({:roll, 1}) == FrenchCurve.image_id({:roll, 2})
      assert FrenchCurve.image_id("anything") in 1..4_000_000_000
    end
  end

  describe "render/3 with an explicit protocol" do
    test "braille returns cell rows, not the string to_terminal/3 would give" do
      assert [[{_char, _color} | _] | _] = FrenchCurve.render(sample(), :braille, [])
    end
  end

  describe "render/2" do
    test "honors an explicit :protocol option" do
      assert String.starts_with?(FrenchCurve.render(sample(), protocol: :kitty), "\e_G")
    end

    test "auto-detects when no protocol is given" do
      assert FrenchCurve.render(sample()) != nil
    end
  end

  describe "to_terminal/3" do
    test "braille returns a printable ANSI string, not cell rows" do
      output = FrenchCurve.to_terminal(sample(), :braille)
      assert is_binary(output)
      assert output =~ ~r/[\x{2800}-\x{28FF}]/u
    end

    test "pixel backends return their escape string unchanged" do
      assert String.starts_with?(FrenchCurve.to_terminal(sample(), :kitty), "\e_G")
      assert String.starts_with?(FrenchCurve.to_terminal(sample(), :sixel), "\eP")
      assert String.starts_with?(FrenchCurve.to_terminal(sample(), :iterm2), "\e]1337")
    end
  end
end
