defmodule Comn.MixProject do
  use Mix.Project

  def project do
    [
      app: :comn,
      version: "0.4.0",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :inets]
    ]
  end

  defp deps do
    [
      {:gnat, "~> 1.11"},
      {:jason, "~> 1.4"},
      {:req, "~> 0.5"},
      {:libgraph, "~> 0.16"},
      {:faker, "~> 0.18", only: :test}
    ]
  end
end
