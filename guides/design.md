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

<a id="cross-cutting"></a>
## Cross-cutting Concerns — Context, Errors, Events

Contexts, Errors, and Events are three independent subsystems. None depends on
the other two. What ties them together is ambient process state: a single
`ContextStruct` stored in the process dictionary at the request boundary
automatically enriches every error and every event produced downstream — without
any function in between needing to know or forward it.

<a id="contexts"></a>
### Contexts

The alternative to ambient context is explicit parameter threading: every
function in the call chain accepts a context argument and passes it to every
function it calls. At shallow call depths that is fine. Across a library with
many independent subsystems it becomes a forcing function that pollutes every
function signature and couples subsystems to the context type. Logger metadata
and OpenTelemetry baggage both reject that approach for the same reason — and
both use the process dictionary instead. Comn follows the same pattern.

`Comn.Contexts.new/1` constructs a `ContextStruct` from keyword fields and
stores it in the process dictionary under a fixed key. `fetch/1` reads it back.
`with_context/2` provides a scoped override: it sets the new context, runs the
function, and restores the previous value (or deletes the key if there was none)
via `try/after`, guaranteeing no leakage even if the function raises.

```elixir
<!-- from lib/comn/contexts.ex -->
@key :comn_context

def new(fields) do
  ctx = ContextStruct.new(fields)
  set(ctx)
  ctx
end

def with_context(%ContextStruct{} = ctx, fun) do
  old = get()
  set(ctx)
  try do
    fun.()
  after
    case old do
      nil -> Process.delete(@key)
      prev -> set(prev)
    end
  end
end
```

Fields that propagate: `request_id`, `trace_id`, `correlation_id`, `user_id`,
`actor`, `env`, `zone`, `parent_event_id`, `metadata`. Any field not set
defaults to `nil` — callers set only what they have.

<a id="error-philosophy"></a>
### Errors

Bare atoms fail at the boundary. They carry no context, no suggested remediation,
no HTTP status for callers that need one. They cannot be queried by category.
They offer nothing to an operator reading logs or a client deciding whether to
retry.

Every Comn error is a full `ErrorStruct` with a registered `namespace/error_name`
code. The code format is enforced by regex at compile time — an invalid format is
a `CompileError`, not a runtime surprise. Duplicate codes within a module are
rejected. The struct is enriched from ambient context: `request_id`, `trace_id`,
and `correlation_id` are pulled from the process dictionary automatically, so
errors carry provenance without any call site doing anything extra.

Six categories cover the domain: `:validation`, `:persistence`, `:network`,
`:auth`, `:internal`, `:unknown`. The `categorize/1` heuristic uses keyword
matching on the error code string — not exhaustive, but useful for
auto-categorizing errors that weren't explicitly registered with a category.
Errors are also queryable by HTTP status code and by code prefix, enabling a
caller to ask "does this module produce any 5xx errors?" without reading source.

The `Comn.Error` protocol provides `wrap/1`, which converts any term into an
`ErrorStruct` via protocol dispatch. Strings, maps, `{:error, reason}` tuples,
and existing structs all have implementations. The goal: no error escapes the
subsystem as a raw term.

The compile-time registry is built by the `register_error` macro. Each call
accumulates a map into a module attribute. At boot, `Comn.Discovery` scans
loaded modules for `__errors__/0` and indexes all registered codes into
`:persistent_term`. The result is a queryable registry of every error the system
can produce.

```elixir
<!-- from lib/comn/errors/registry.ex -->
defmacro register_error(code, category, opts) do
  unless is_binary(code) and Regex.match?(~r/^[a-z][a-z0-9]*(\.[a-z][a-z0-9]*)*\/[a-z][a-z0-9_]*$/, code) do
    raise CompileError,
      description: "invalid error code #{inspect(code)} — must match namespace/error_name"
  end

  quote do
    @registered_errors %{
      code: unquote(code),
      category: unquote(category),
      message: unquote(Keyword.get(opts, :message)),
      status: unquote(Keyword.get(opts, :status)),
      suggestion: unquote(Keyword.get(opts, :suggestion)),
      module: __MODULE__
    }
  end
end
```

<a id="events"></a>
### Events

`Comn.Events` is a behaviour — it defines four callbacks (`start_link`,
`broadcast`, `subscribe`, `unsubscribe`) and leaves the transport to adapters.
Two adapters ship with the library: `Comn.EventBus` (Registry-based, in-process,
no dependencies) and `Comn.Events.Registry` (a named variant of the same
pattern). A third adapter, `Comn.Events.NATS`, targets external pub/sub but is
opt-in: Comn cannot know the connection configuration, so it cannot initialize
NATS itself. Applications that need it configure and start the adapter explicitly.

`EventStruct.new/5` mirrors the error enrichment pattern. The constructor reads
the ambient `ContextStruct` and copies `request_id` and `correlation_id` into
the event without the call site doing anything. Every event produced during a
request automatically carries the same provenance as every error produced during
that same request.

`EventLog` is an Agent wrapping an append-only list. It works for development
and low-volume use cases. Known limitation: the list is unbounded. Nothing
prunes it. For production use, consume events and drain the log or use an
external adapter.

```elixir
<!-- from lib/comn/events/event_struct.ex -->
def new(type, topic, data, source \\ __MODULE__, opts \\ []) do
  ctx = Comn.Contexts.get()

  %__MODULE__{
    id: Comn.Secrets.Local.UUID.uuid4(),
    timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
    source: source,
    type: type,
    topic: topic,
    data: data,
    schema: Keyword.get(opts, :schema),
    version: Keyword.get(opts, :version, 1),
    tags: Keyword.get(opts, :tags, []),
    correlation_id: ctx && ctx.correlation_id,
    request_id: ctx && ctx.request_id,
    metadata: Keyword.get(opts, :metadata, %{})
  }
end
```

<a id="composition"></a>
### The Composition Story

The three subsystems compose without any explicit coordination. Set a context
once at the request boundary — every error and every event produced anywhere in
the call stack carries that context automatically:

```elixir
# Set context once at the request boundary
Comn.Contexts.new(request_id: "req-abc", trace_id: "trace-789", user_id: "user-42")

# Somewhere deep in the call stack, an error occurs — auto-enriched
{:ok, error} = Comn.Errors.wrap("database_timeout")
error.request_id      #=> "req-abc"
error.trace_id        #=> "trace-789"

# An event is broadcast — also auto-enriched from the same context
event = Comn.Events.EventStruct.new(:domain, "order.failed", %{reason: "timeout"})
event.request_id      #=> "req-abc"
event.correlation_id  #=> nil (not set in this context)

# Both carry the same request_id without anyone passing it explicitly
```

No function in the call chain between the boundary and the error or event site
needed to accept or forward a context argument. The process dictionary carries
it. Same pattern Logger uses for metadata — idiomatic BEAM, not a hack.
