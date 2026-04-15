# The Design of Comn

<a id="the-principle"></a>
## The Problem and the Principle

In a system with many modules, discovering what exists and what it can do
requires reading documentation or source. You either know the module's name
and hope the docs are current, or you grep. Neither scales, and neither is
available at runtime to an orchestration layer, a TUI, or an agent that needs
to navigate the system programmatically.

Comn's answer is a four-verb introspection protocol. Every module that declares
`@behaviour Comn` answers the same four questions:

- `look/0` — what is this? (human-readable summary)
- `recon/0` — what can it do? (machine-readable metadata map)
- `choices/0` — what are my options? (available inputs, adapters, modes)
- `act/1` — do it (execute with a map of inputs)

The four verbs are drawn from the OODA loop in the Anemos design: Observe,
Orient, Decide, Act. `look` and `recon` are observing; `choices` is orienting;
`act` is acting. The loop is the same whether the caller is a human at a
terminal or a process coordinating a pipeline.

Three module types implement this contract differently:

- **Behaviour modules** (e.g. `Comn.Repo`, `Comn.Events`) define the contract.
  They answer `look`, `recon`, and `choices` with metadata about what
  implementations must provide. Their `act/1` returns `{:error, :behaviour_only}`
  — they describe the shape, they don't do the work.
- **Implementation modules** (e.g. `Comn.Repo.Table.ETS`) do the work.
  Their `recon/0` reports `:type => :implementation` and their `act/1`
  executes against real infrastructure.
- **Facade modules** orchestrate. They may compose multiple implementations,
  route based on configuration, or wrap an external API. Their `:type` is
  `:facade`.

Why this matters: orchestration layers, TUIs, CLI tools, and autonomous agents
can navigate the entire system without reading source. A process can call
`Comn.Repo.choices/0` to find all available implementations, select one, call
its `recon/0` to confirm it supports the required callbacks, then call `act/1`
with the appropriate inputs. Discovery is not documentation — it is live
metadata, queryable at runtime, always in sync with the code.

The behaviour definition:

```elixir
<!-- from lib/comn/comn.ex -->
@callback look() :: String.t()
@callback recon() :: map()
@callback choices() :: map()
@callback act(map()) :: {:ok, term()} | {:error, term()}
```

The discovery loop in action against `Comn.Repo`:

```elixir
Comn.Repo.look()
#=> "Repo — common I/O behaviour for data repositories (tables, files, graphs, commands)"

Comn.Repo.recon()
#=> %{callbacks: [:describe, :get, :set, :delete, :observe],
#     extensions: [Comn.Repo.Table, Comn.Repo.File, Comn.Repo.Graphs, Comn.Repo.Cmd],
#     type: :behaviour}

Comn.Repo.choices()
#=> %{extensions: ["Table", "File", "Graphs", "Cmd"],
#     implementations: ["Table.ETS", "File.Local", ...]}

Comn.Repo.Table.ETS.act(%{action: :create, name: :my_table})
#=> {:ok, #Reference<...>}
```
