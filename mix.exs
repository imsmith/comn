defmodule Comn.MixProject do
  @moduledoc false
  use Mix.Project

  def project do
    [
      app: :comn,
      version: "0.6.2",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      name: "Comn",
      docs: [
        main: "readme",
        extras: [
          "README.md",
          "guides/design.md",
          "docs/adr/0001-every-repo-shape-is-an-event-sink.md"
        ]
      ],
      dialyzer: [plt_add_apps: [:mix]]
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
      {:plug_crypto, "~> 2.0"},
      {:exqlite, "~> 0.27"},
      {:ecto_sql, "~> 3.12", optional: true},
      {:ecto_sqlite3, "~> 0.21", only: :test},
      {:stream_data, "~> 1.1", only: [:dev, :test]},
      {:faker, "~> 0.18", only: :test},
      {:ex_doc, "~> 0.38", only: :dev, runtime: false},
      {:credo, "~> 1.7", optional: true, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.14", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      # Local checkout until the exponential walk in vet_core is fixed upstream;
      # see ~/github/vet/ISSUES.md.
      {:vet_cli, path: Path.expand("~/github/vet/apps/vet_cli"), only: [:dev, :test], runtime: false}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
