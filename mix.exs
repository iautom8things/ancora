defmodule Ancora.MixProject do
  use Mix.Project

  @version "1.2.0"
  @source_url "https://github.com/iautom8things/ancora"

  def project do
    [
      app: :ancora,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      source_url: @source_url,
      homepage_url: @source_url,
      docs: [
        main: "readme",
        extras: ["README.md", "CHANGELOG.md", "LICENSE", "NOTICE", "docs/migration.md"],
        groups_for_modules: [
          "Public API": [Ancora, Ancora.Parser, Ancora.DecisionParser],
          Internal: ~r/.*/
        ]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:yaml_elixir, "~> 2.11"},
      {:zoi, "~> 0.17"},
      {:jason, "~> 1.4"},
      {:earmark_parser, "~> 1.4"},
      {:stream_data, "~> 1.0", only: [:dev, :test]},
      {:ex_doc, "~> 0.38", only: :dev, runtime: false}
    ]
  end

  defp description do
    "Spec-anchored traceability and drift detection for Elixir."
  end

  defp package do
    [
      files:
        ~w(lib priv/spec_init priv/spec_review_assets .formatter.exs mix.exs README.md CHANGELOG.md LICENSE NOTICE docs/migration.md),
      licenses: ["MIT"],
      links: %{
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md",
        "GitHub" => @source_url
      }
    ]
  end
end
