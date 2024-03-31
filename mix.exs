defmodule S3.MixProject do
  use Mix.Project

  @source_url "https://github.com/ruslandoga/s3"
  @version "0.1.0-rc.0"

  def project do
    [
      app: :s3,
      version: @version,
      elixir: "~> 1.15",
      deps: deps(),
      name: "S3",
      description: "Minimal request builder for S3-compatible object storage API",
      docs: docs(),
      package: package(),
      source_url: @source_url
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :crypto, :xmerl]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:finch, "~> 0.18.0", only: [:dev, :test]},
      {:jason, "~> 1.4", only: [:dev, :test]},
      {:aws_signature, "~> 0.3.1", only: [:test, :bench]},
      {:benchee, "~> 1.2", only: :bench},
      {:sweet_xml, "~> 0.7.4", only: [:test, :bench]},
      {:saxy, "~> 1.5", only: [:test, :bench]},
      {:meeseeks, "~> 0.17.0", only: [:test, :bench]},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, ">= 0.0.0", only: :docs}
    ]
  end

  defp docs do
    [
      source_url: @source_url,
      source_ref: "v#{@version}",
      main: "readme",
      extras: ["README.md", "CHANGELOG.md"],
      skip_undefined_reference_warnings_on: ["CHANGELOG.md"]
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end
end
