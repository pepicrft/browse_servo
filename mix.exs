defmodule BrowseServo.MixProject do
  use Mix.Project

  @version "0.1.0-dev"
  @source_url "https://github.com/pepicrft/browse_servo"

  def project do
    [
      app: :browse_servo,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      package: package(),
      aliases: aliases(),
      description: "Rustler-backed Elixir browser runtime for Servo-powered browser workflows",
      elixirc_paths: elixirc_paths(Mix.env()),
      name: "BrowseServo",
      source_url: @source_url
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:browse, "~> 0.1.0"},
      {:telemetry, "~> 1.3"},
      {:rustler_precompiled, "~> 0.8.4"},
      {:rustler, "~> 0.37.3", optional: true},
      {:mimic, "~> 2.3", only: :test},
      {:quokka, "~> 2.12", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp docs do
    [
      main: "BrowseServo",
      extras: ["README.md"],
      source_ref: @version,
      source_url: @source_url
    ]
  end

  defp package do
    [
      files: ~w(
        .formatter.exs
        CHANGELOG.md
        LICENSE
        README.md
        checksum-*.exs
        config
        lib
        mix.exs
        native
      ),
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get"],
      lint: ["format --check-formatted", "credo --strict"],
      test: ["test"]
    ]
  end
end
