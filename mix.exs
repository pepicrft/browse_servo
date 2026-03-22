defmodule Lightpanda.MixProject do
  use Mix.Project

  @version "0.1.0-dev"
  @source_url "https://github.com/pepicrft/lightpanda"

  def project do
    [
      app: :lightpanda,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      package: package(),
      aliases: aliases(),
      description: "Elixir-native wrapper around the Lightpanda browser",
      elixirc_paths: elixirc_paths(Mix.env()),
      name: "Lightpanda",
      source_url: @source_url
    ]
  end

  def application do
    [
      extra_applications: [:crypto, :logger],
      mod: {Lightpanda.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:req, "~> 0.5.17"},
      {:websockex, "~> 0.5.1"},
      {:zigler_precompiled, "~> 0.1.2"},
      {:zigler, "~> 0.15.2", optional: true, runtime: false},
      {:mimic, "~> 2.3", only: :test},
      {:quokka, "~> 2.12", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.38", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp docs do
    [
      main: "Lightpanda",
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
      setup: ["deps.get", "zig.get"],
      lint: ["format --check-formatted", "credo --strict"],
      test: ["test"]
    ]
  end
end
