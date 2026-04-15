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

<a id="discovery"></a>
## Discovery — The System Knows Itself

If every module answers four questions, the system can ask all of them at once.
`Comn.Discovery` does exactly that: at boot it scans every loaded module,
identifies those that export all four Comn callbacks, calls `recon/0` on each,
and stores the result in `:persistent_term`. From that point on, the index costs
nothing to read and is available to any process on the node.

### How It Works

`Comn.Discovery.discover/0` runs during `Comn.Application` startup. It iterates
`:code.all_loaded/0` — the BEAM's list of currently loaded modules — and filters
for modules that export `look/0`, `recon/0`, `choices/0`, and `act/1`. Each
match gets a metadata map built from its `recon/0` and `look/0` return values.
The full index is written once to `:persistent_term` under a fixed key.

```elixir
<!-- from lib/comn/discovery.ex -->
def discover do
  Enum.each(@comn_modules, &Code.ensure_loaded/1)

  index =
    for {module, _} <- :code.all_loaded(),
        comn_module?(module),
        into: %{} do
      {module, build_meta(module)}
    end

  :persistent_term.put(@persistent_term_key, index)
  :ok
end
```

### The Lazy-Loading Problem

The BEAM loads modules on first reference, not at startup. A module sitting in
the code path but never yet called won't appear in `:code.all_loaded/0`. Comn's
own modules are listed explicitly in `@comn_modules` and passed through
`Code.ensure_loaded/1` before the scan runs — that guarantees they are in
memory before the filter runs, regardless of whether any caller has touched them
yet.

Consumer modules — `MyApp.Repo.Postgres`, `MyApp.Events.NATSBridge`, whatever
the application defines — are not known to Comn at compile time. They are picked
up automatically if they have been loaded before `discover/0` runs. In practice
this means placing `Comn.Application` early in your supervision tree so that
application modules are loaded by the time discovery executes.

### Query API

```elixir
# All discovered modules
Comn.Discovery.all()
#=> [Comn.Contexts, Comn.Errors, Comn.Events, Comn.Infra, Comn.Repo, ...]

# Filter by type
Comn.Discovery.by_type(:behaviour)
#=> [Comn.Repo, Comn.Events, Comn.Secrets, ...]

Comn.Discovery.by_type(:implementation)
#=> [Comn.Repo.Table.ETS, Comn.Repo.File.Local, ...]

# All implementations of a specific behaviour
Comn.Discovery.implementations_of(Comn.Repo.File)
#=> [Comn.Repo.File.Local, Comn.Repo.File.NFS, Comn.Repo.File.IPFS]

# Full metadata for a module
Comn.Discovery.lookup(Comn.Repo.Table.ETS)
#=> %{module: Comn.Repo.Table.ETS, look: "ETS — ...", type: :implementation,
#     extends: [Comn.Repo.Table], choices: %{...}, recon: %{...}}
```

### Design Rationale: `persistent_term` Over ETS

The index is read on every discovery query and written once at boot.
`:persistent_term` is the right tool for that shape: reads are a direct memory
access with no process coordination, no lock, and no copying — effectively free.
The tradeoff is writes: updating a `:persistent_term` entry triggers a global GC
pass across all processes on the node, because the runtime must invalidate cached
references to the old value. For a registry written once at startup that cost is
irrelevant. For anything updated frequently it would be a serious problem. ETS
would be the right choice there; here it is unnecessary overhead.

### Design Rationale: Runtime Scan Over Compile-Time Registry

A compile-time registry — a module attribute accumulating implementations via
`use Comn.Repo` or similar — would only capture modules compiled after Comn
itself. Consumer application modules don't exist at Comn's compile time; they
can't register themselves in Comn's module attributes. A runtime scan has no
such constraint. Any module loaded on the node, from any application, is
visible. The protocol is the registry: export the four callbacks, and you appear
in the index.
