defmodule FrenchCurve.Backend.Kitty do
  @moduledoc false

  alias FrenchCurve.Raster

  @chunk_size 4096

  @spec render(Raster.t(), keyword) :: binary
  def render(%Raster{} = raster, opts \\ []) do
    {width, height} = Raster.dimensions(raster)
    fit = fit_control(Keyword.get(opts, :fit))

    raster
    |> Raster.to_rgba_binary()
    |> Base.encode64()
    |> chunk(@chunk_size)
    |> emit(width, height, fit)
  end

  defp fit_control(nil), do: ""
  defp fit_control({cols, rows}), do: ",c=#{cols},r=#{rows}"

  defp emit([only], width, height, fit) do
    sequence("a=T,f=32,s=#{width},v=#{height}#{fit},m=0", only)
  end

  defp emit([first | rest], width, height, fit) do
    sequence("a=T,f=32,s=#{width},v=#{height}#{fit},m=1", first) <> emit_rest(rest)
  end

  defp emit_rest([last]), do: sequence("m=0", last)
  defp emit_rest([part | rest]), do: sequence("m=1", part) <> emit_rest(rest)

  @spec transmit(Raster.t(), pos_integer) :: binary
  def transmit(%Raster{} = raster, id) do
    raster
    |> Raster.to_rgba_binary()
    |> Base.encode64()
    |> chunk(@chunk_size)
    |> emit_transmit(id, Raster.dimensions(raster))
  end

  @spec place(pos_integer, keyword) :: binary
  def place(id, opts \\ []) do
    control =
      ["a=p", "i=#{id}", "q=2", "C=1"] ++
        placement_part(opts[:placement]) ++ z_part(opts[:z]) ++ fit_part(opts[:fit])

    command(Enum.join(control, ","))
  end

  @spec delete(keyword) :: binary
  def delete(opts) do
    control =
      ["a=d", "d=i", "i=#{Keyword.fetch!(opts, :id)}", "q=2"] ++ placement_part(opts[:placement])

    command(Enum.join(control, ","))
  end

  defp emit_transmit([only], id, {width, height}) do
    sequence("a=t,i=#{id},f=32,s=#{width},v=#{height},q=2,m=0", only)
  end

  defp emit_transmit([first | rest], id, {width, height}) do
    sequence("a=t,i=#{id},f=32,s=#{width},v=#{height},q=2,m=1", first) <> emit_rest(rest)
  end

  defp placement_part(nil), do: []
  defp placement_part(placement), do: ["p=#{placement}"]

  defp z_part(nil), do: []
  defp z_part(z), do: ["z=#{z}"]

  defp fit_part(nil), do: []
  defp fit_part({cols, rows}), do: ["c=#{cols}", "r=#{rows}"]

  defp command(control), do: "\e_G" <> control <> "\e\\"

  defp sequence(control, payload), do: "\e_G" <> control <> ";" <> payload <> "\e\\"

  defp chunk(binary, size) do
    case binary do
      <<part::binary-size(size), rest::binary>> when byte_size(rest) > 0 ->
        [part | chunk(rest, size)]

      other ->
        [other]
    end
  end
end
