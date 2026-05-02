defmodule Comn.MixProject do
  @moduledoc false
  use Mix.Project

  def project do
    [
      app: :comn,
      version: "0.5.0",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env())
    ]
  end

  def application do
    [
      extra_applications: [:logger, :inets],
      mod: {Comn.Application, []}
    ]
  end

  defp deps do
    [
      {:gnat, "~> 1.11"},
      {:jason, "~> 1.4"},
      {:req, "~> 0.5"},
      {:libgraph, "~> 0.16"},
      {:exqlite, "~> 0.27"},
      {:stream_data, "~> 1.1", only: [:dev, :test]},
      {:faker, "~> 0.18", only: :test}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_),     do: ["lib"]
end
