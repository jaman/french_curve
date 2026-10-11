defmodule FrenchCurve.MixProject do
  use Mix.Project

  @version "0.2.0"
  @source_url "https://github.com/jaman/french_curve"

  def project do
    [
      app: :french_curve,
      version: @version,
      elixir: "~> 1.19",
      compilers: [:elixir_make | Mix.compilers()],
      make_targets: ["all"],
      make_clean: ["clean"],
      make_env: %{"PRIV_DIR" => "priv/native/#{:erlang.system_info(:system_architecture)}"},
      start_permanent: Mix.env() == :prod,
      elixirc_options: [warnings_as_errors: true],
      deps: deps(),
      name: "FrenchCurve",
      description: description(),
      package: package(),
      docs: docs(),
      source_url: @source_url,
      plumb: [readme: :exact]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp description do
    "Terminal graphics for Elixir. Draw charts, curves and sprites into an RGBA " <>
      "raster and emit it over the kitty, sixel, iTerm2 or braille protocol."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files:
        ~w(lib c_src examples Makefile Makefile.win .formatter.exs mix.exs README.md CHANGELOG.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extras: ["README.md", "CHANGELOG.md", "LICENSE"],
      groups_for_modules: [
        Drawing: [
          FrenchCurve.Raster,
          FrenchCurve.Draw,
          FrenchCurve.Chart,
          FrenchCurve.Curve
        ],
        Backends: [
          FrenchCurve.Backend.Kitty,
          FrenchCurve.Backend.Sixel,
          FrenchCurve.Backend.Iterm2,
          FrenchCurve.Backend.Braille
        ],
        Sprites: [
          FrenchCurve.Sprite,
          FrenchCurve.Sprite.Registry
        ],
        Terminal: [
          FrenchCurve.Capability,
          FrenchCurve.Geometry
        ],
        Encoding: [
          FrenchCurve.Png
        ]
      ]
    ]
  end

  defp deps do
    [
      {:elixir_make, "~> 0.9", runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:plumb, "~> 0.2", only: :dev, runtime: false}
    ]
  end
end
