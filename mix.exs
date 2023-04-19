defmodule DartSass.MixProject do
  use Mix.Project

  @version "0.6.0"
  @source_url "https://github.com/CargoSense/dart_sass"

  def project do
    [
      app: :dart_sass,
      version: @version,
      elixir: "~> 1.10",
      deps: deps(),
      description: "Mix tasks for installing and invoking sass",
      package: [
        links: %{
          "GitHub" => @source_url,
          "dart-sass" => "https://sass-lang.com/dart-sass"
        },
        licenses: ["MIT"]
      ],
      docs: [
        main: "DartSass",
        source_url: @source_url,
        source_ref: "v#{@version}",
        extras: ["CHANGELOG.md"]
      ],
      aliases: [test: ["sass.install --if-missing", "test"]]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :inets, :ssl],
      mod: {DartSass, []},
      env: [default: []]
    ]
  end

  defp deps do
    [
      {:castore, ">= 0.0.0"},
      {:ex_doc, ">= 0.0.0", only: :docs}
    ]
  end
end
