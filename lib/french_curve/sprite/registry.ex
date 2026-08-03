defmodule FrenchCurve.Sprite.Registry do
  @moduledoc """
  Remembers which sprite ids have been uploaded, so a render loop uploads each one once.

  A plain immutable value, not a process: thread it through your render state and replace
  it with the one `ensure/3` hands back.

      {registry, bytes} = FrenchCurve.Sprite.Registry.ensure(registry, sprite, :kitty)
      IO.write(bytes <> FrenchCurve.Sprite.place(sprite, :kitty))

  The registry tracks ids, not terminals. Start a fresh one whenever the terminal's image
  store is emptied, or it will assume uploads that no longer exist.
  """

  alias FrenchCurve.Sprite

  @enforce_keys [:uploaded]
  defstruct uploaded: MapSet.new()

  @type t :: %__MODULE__{uploaded: MapSet.t(pos_integer)}

  @doc """
  Returns an empty registry.
  """
  @spec new() :: t
  def new, do: %__MODULE__{uploaded: MapSet.new()}

  @doc """
  Returns `{registry, bytes}`, uploading `sprite` if this registry has not seen its id.

  `bytes` is the upload sequence the first time a given id is passed under `:kitty`, and
  `""` on every later call and for every other protocol. The returned registry records the
  id and must be used in place of the one passed in.
  """
  @spec ensure(t, Sprite.t(), atom) :: {t, binary}
  def ensure(%__MODULE__{} = registry, %Sprite{} = sprite, :kitty) do
    if MapSet.member?(registry.uploaded, sprite.id) do
      {registry, ""}
    else
      updated = %{registry | uploaded: MapSet.put(registry.uploaded, sprite.id)}
      {updated, Sprite.upload(sprite, :kitty)}
    end
  end

  def ensure(%__MODULE__{} = registry, %Sprite{}, protocol) when is_atom(protocol) do
    {registry, ""}
  end
end
