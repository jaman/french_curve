defmodule FrenchCurve.Sprite.Registry do
  @moduledoc false

  alias FrenchCurve.Sprite

  @enforce_keys [:uploaded]
  defstruct uploaded: MapSet.new()

  @type t :: %__MODULE__{uploaded: MapSet.t(pos_integer)}

  @spec new() :: t
  def new, do: %__MODULE__{uploaded: MapSet.new()}

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
