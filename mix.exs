defmodule S3.MixProject do
  use Mix.Project

  def project do
    [
      app: :s3,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps()
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
      {:finch, "~> 0.16.0", only: [:dev, :test]},
      {:aws_signature, "~> 0.3.1", only: [:test, :bench]},
      {:benchee, "~> 1.2", only: :bench},
      {:sweet_xml, "~> 0.7.4", only: :bench},
      {:saxy, "~> 1.5", only: :bench},
      {:meeseeks, "~> 0.17.0", only: :bench}
    ]
  end
end
