defmodule FrenchCurve.Deflate do
  @moduledoc """
  Compresses a picture into the zlib format a terminal expects, with libdeflate where it
  is built and `:zlib` where it is not.

      FrenchCurve.Deflate.compress(pixels)
      FrenchCurve.Deflate.compress(pixels, 6)

  The kitty graphics protocol takes its payload deflated and marked `o=z`, which means
  the zlib wrapper of RFC 1950 rather than a bare deflate stream. Both paths here
  produce that, so a terminal cannot tell them apart; they differ only in how long they
  take and how small they get.

  `level` runs `1` to `12` for libdeflate and is clamped to `1..9` for `:zlib`, which has
  no levels above nine. Higher is smaller and slower. The default, `#{6}`, is what
  `:zlib.compress/1` uses.

  `available?/0` says whether libdeflate is in use.
  """

  @on_load :load_nif

  @default 6

  @doc false
  def load_nif do
    :french_curve
    |> :code.priv_dir()
    |> Path.join("deflate_nif")
    |> to_charlist()
    |> :erlang.load_nif(0)
    |> case do
      :ok -> :persistent_term.put({__MODULE__, :native?}, true)
      {:error, _reason} -> :ok
    end

    :ok
  end

  @doc "Whether libdeflate is built and loaded."
  @spec available?() :: boolean()
  def available?, do: :persistent_term.get({__MODULE__, :native?}, false)

  @doc "`data` compressed into the zlib format, at `level`."
  @spec compress(binary(), 1..12) :: binary()
  def compress(data, level \\ @default) when is_binary(data) do
    if available?(), do: deflate(data, level), else: with_zlib(data, level)
  end

  @doc false
  @spec deflate(binary(), integer()) :: binary()
  def deflate(_data, _level), do: :erlang.nif_error(:not_loaded)

  defp with_zlib(data, level) do
    stream = :zlib.open()

    try do
      :zlib.deflateInit(stream, level |> min(9) |> max(1))
      compressed = :zlib.deflate(stream, data, :finish)
      :zlib.deflateEnd(stream)
      IO.iodata_to_binary(compressed)
    after
      :zlib.close(stream)
    end
  end
end
