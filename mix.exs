defmodule Ancora.MixProject do
  use Mix.Project

  @version "0.1.0"
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
      homepage_url: @source_url
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
      {:stream_data, "~> 1.0", only: [:dev, :test]}
    ]
  end

  defp description do
    "Spec-anchored traceability and drift detection for Elixir."
  end

  # Stub: Hex files/extra links land at publish (L14).
  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end
end
