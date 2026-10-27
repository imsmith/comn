defmodule Comn.MixProject do
  @moduledoc false
  use Mix.Project

  def project do
    [
      app: :comn,
      version: "0.7.0",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      name: "Comn",
      docs: [
        main: "readme",
        extras: [
          "README.md",
          "CHANGELOG.md",
          "guides/design.md",
          "docs/adr/0001-every-repo-shape-is-an-event-sink.md"
        ],
        groups_for_modules: [
          Core: [Comn, Comn.Discovery, Comn.Supervisor, Comn.Application],
          "Context, errors, events": [
            Comn.Contexts,
            Comn.Context,
            Comn.Contexts.ContextStruct,
            Comn.Contexts.PolicyStruct,
            Comn.Contexts.RuleStruct,
            Comn.Errors,
            Comn.Error,
            Comn.Errors.ErrorStruct,
            Comn.Errors.Registry,
            Comn.Errors.Core,
            Comn.Events,
            Comn.Event,
            Comn.Events.EventStruct,
            Comn.EventBus,
            Comn.EventLog,
            Comn.Events.NATS,
            Comn.Events.Registry,
            Comn.Events.Errors
          ],
          Spatial: [Comn.Zone, Comn.Presence],
          "Repo: facades": [
            Comn.Repo,
            Comn.Repo.Handle,
            Comn.Repo.Lifecycle,
            Comn.Repo.Table,
            Comn.Repo.Column,
            Comn.Repo.File,
            Comn.Repo.Graphs,
            Comn.Repo.Batch,
            Comn.Repo.Queue,
            Comn.Repo.Bus,
            Comn.Repo.Stream,
            Comn.Repo.Merkel,
            Comn.Repo.Cmd,
            Comn.Repo.Actor,
            Comn.Repo.Errors
          ],
          "Repo: backends": [
            Comn.Repo.Table.ETS,
            Comn.Repo.Table.Ecto,
            Comn.Repo.Table.Ecto.EventRow,
            Comn.Repo.Table.Ecto.Term,
            Comn.Repo.Column.ETS,
            Comn.Repo.File.Local,
            Comn.Repo.File.NFS,
            Comn.Repo.File.IPFS,
            Comn.Repo.File.Root,
            Comn.Repo.File.FileStruct,
            Comn.Repo.Graphs.Graph,
            Comn.Repo.Graphs.GraphStruct,
            Comn.Repo.Batch.Mem,
            Comn.Repo.Queue.Mem,
            Comn.Repo.Queue.SQLite,
            Comn.Repo.Queue.Errors,
            Comn.Repo.Bus.Registry,
            Comn.Repo.Stream.Mem,
            Comn.Repo.Stream.SQLite,
            Comn.Repo.Stream.JetStream,
            Comn.Repo.Merkel.Mem,
            Comn.Repo.Merkel.Git,
            Comn.Repo.Merkel.Node,
            Comn.Merkel,
            Comn.Repo.Cmd.Shell
          ],
          Secrets: [
            Comn.Secrets,
            Comn.Secret,
            Comn.Secrets.Local,
            Comn.Secrets.Vault,
            Comn.Secrets.Utils,
            Comn.Secrets.Key,
            Comn.Secrets.LockedBlob,
            Comn.Secrets.Container,
            Comn.Secrets.Errors
          ],
          "Credo checks": [
            Comn.Credo.Check,
            Comn.Credo.BareErrorAtom,
            Comn.Credo.SecretFromEnv,
            Comn.Credo.RawShell
          ],
          Infra: [
            Comn.Infra,
            Comn.Infra.Compute,
            Comn.Infra.Storage,
            Comn.Infra.Connectivity,
            Comn.Infra.Linux,
            Comn.Infra.Proxmox,
            Comn.Infra.Unifi
          ]
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
      {:vet_cli,
       path: Path.expand("~/github/vet/apps/vet_cli"), only: [:dev, :test], runtime: false}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
