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
      {:finch, "~> 0.16.0", only: :dev},
      {:aws_signature, "~> 0.3.1", only: :test}
    ]
  end
end
