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

<a id="secrets"></a>
## Secrets — Encryption Without Lifecycle

### Philosophy

Secrets are encrypted data. That's the entire model.

No rotation schedules. No version stages. No key management opinions. No
lifecycle state machine. If you want rotation, call `lock/2` again with the new
key and store the result. If you want versioning, store multiple blobs. The
library's job is to encrypt and decrypt — yours is to decide when, with what
key, and for how long.

Four verbs: `lock`, `unlock`, `wrap`, `unwrap`. `lock` encrypts a binary.
`unlock` decrypts it. `wrap` encrypts a list of blobs as a single container.
`unwrap` recovers the list. Nothing else belongs here.

The "no lifecycle" stance is a deliberate choice, not an omission. Lifecycle
management is a policy problem. Every system has different rotation windows,
different key storage constraints, different compliance requirements. A library
that bakes in lifecycle assumptions is a library that forces those assumptions on
its callers. `Comn.Secrets` refuses to do that.

### Why ChaCha20-Poly1305

ChaCha20-Poly1305 is an AEAD cipher — authentication and encryption in one pass.
The authentication tag covers both the ciphertext and the additional authenticated
data (AAD), so tampering with either is detectable at decrypt time, not as a
separate MAC step.

It's a stream cipher, not a block cipher, so there are no padding oracle attacks.
The 96-bit nonce space is large enough for reasonable volumes when nonces are
generated with a CSPRNG — no nonce-reuse risk from counter overflow at practical
scale. Erlang's `:crypto` module exposes it natively via OpenSSL.

### Key Derivation

Ed25519 keys are asymmetric signature keys. ChaCha20-Poly1305 needs a symmetric
32-byte key. The bridge is SHA-256: the private key material is hashed to derive
the symmetric key.

This is correct — the derived key is uniformly distributed and the right length.
It is not best-practice. Production use should use HKDF (RFC 5869) with an
explicit info string and salt to separate key purposes and prevent cross-protocol
key reuse. The current approach is a pragmatic starting point; the interface does
not change when the derivation is upgraded.

### Wrap/Unwrap Design

`wrap` does not bundle blobs alongside encryption — it encrypts the container as
a whole. The entire serialized `%Container{}` structure, including blob order,
blob count, and metadata, is the plaintext that gets locked.

The AEAD tag therefore covers everything: blob order, blob count, metadata. This
means reordering blobs, deleting a blob from the list, injecting a new blob, or
replaying an old container with a different blob set will all fail authentication.
You cannot surgically modify a wrapped container. The integrity guarantee is
structural, not just per-blob.

### Vault Backend

`Comn.Secrets` is a behaviour. `Comn.Secrets.Local` implements it with Erlang's
`:crypto`. A Vault backend implements the same behaviour, delegating to the
Transit secrets engine.

From the caller's perspective, there is no difference. The function signatures
are identical. Key material never leaves Vault — the backend sends plaintext in,
gets ciphertext back, and Vault handles all key storage, key rotation, and audit
logging internally. Swapping backends is a configuration change, not a code change.

### Safety Detail

All `binary_to_term` calls use the `[:safe]` option. Without it, deserializing
attacker-controlled data can exhaust the atom table (atoms are not garbage
collected) or, in older OTP versions, execute arbitrary code. `[:safe]` restricts
deserialization to terms that reference only existing atoms and does not allow
anonymous functions. Any attempt to deserialize a term with unknown atoms raises
`ArgumentError`, which is caught and converted to a `secrets/invalid_container`
error.

### The `lock/2` Implementation

```elixir
<!-- from lib/comn/secrets/local.ex -->
def lock(blob, %Key{} = key) when is_binary(blob) do
  with :ok <- validate_key(key) do
    symmetric_key = :crypto.hash(:sha256, key.private)
    nonce = :crypto.strong_rand_bytes(12)

    metadata = %{
      created_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      algorithm: key.algorithm
    }

    aad = :erlang.term_to_binary(metadata)

    {ciphertext, tag} = :crypto.crypto_one_time_aead(
      :chacha20_poly1305,
      symmetric_key,
      nonce,
      blob,
      aad,
      true
    )

    {:ok, %LockedBlob{
      cipher: :chacha20_poly1305,
      encrypted: ciphertext,
      tag: tag,
      nonce: nonce,
      key_hint: Key.fingerprint(key),
      metadata: metadata
    }}
  end
end
```

The nonce is fresh per call. The metadata is bound into the AAD before
encryption, so the metadata cannot be swapped out on a stored blob without
breaking authentication. The `with` clause short-circuits on key validation
failure before any crypto work happens.

---

<a id="the-repo-tree"></a>
## The Repo Tree — Ten Shapes of I/O

All I/O falls into a small number of structural patterns. Not every backend is a
relational table, not every data store is mutable, and not every operation is
a read-write pair. Rather than invent a bespoke interface per backend, Comn
defines a behaviour for each structural pattern and lets implementations fill
in the details. The interface stays uniform; the shape of the data and the
lifecycle constraints differ.

### Base Contract: `Comn.Repo`

Every repo type shares five verbs: `describe`, `get`, `set`, `delete`,
`observe`. This is not CRUD with an alias change. The choice of five verbs is
intentional.

`describe` gives introspection CRUD lacks — caller can ask what a resource is,
what its schema is, what its current state is, without fetching data. `observe`
gives streaming and enumeration: a single callback covers both snapshot reads
and live subscriptions. There is no `update` because update is `set` with an
existing key; treating them as distinct operations adds ceremony without adding
capability. The five-verb surface is the lowest common denominator that every
repo type can meaningfully implement, and anything domain-specific belongs in
an extension behaviour layered on top.

```elixir
<!-- from lib/comn/repo.ex -->
@type resource :: term()

@callback describe(resource()) :: {:ok, map()} | {:error, term()}
@callback get(resource(), keyword()) :: {:ok, term()} | {:error, term()}
@callback set(resource(), keyword()) :: :ok | {:ok, term()} | {:error, term()}
@callback delete(resource(), keyword()) :: :ok | {:ok, term()} | {:error, term()}
@callback observe(resource(), keyword()) :: Enumerable.t() | {:error, term()}
```

### The Ten Shapes

**Table** is the baseline: a named collection of key-value pairs with a
create/drop lifecycle. You create the table, put things in it, look them up
by key, drop the table when done. The structure is flat and the semantics are
synchronous. The ETS implementation makes this fast and in-process. What
distinguishes Table from the other shapes is its simplicity — no schema
enforcement, no ordering guarantee, no buffering. It is the raw keyed store
everything else is built toward or away from.

**File** has a state machine lifecycle that none of the other shapes share:
open → load → read/write/stream → close. The state machine is not ceremony;
it exists because using a file before it's loaded or writing to a closed handle
are real, common mistakes that blow up at runtime. Encoding this as a lifecycle
with explicit state transitions catches those errors at the type level rather
than at the point of failure, which may be a hundred calls later. Local, NFS,
and IPFS are all implementations of the same File behaviour — same verbs, same
lifecycle, different path resolution and transport.

**Graphs** is different from Table in kind, not just degree. In a table, data
sits at keys and relationships are implied by convention (foreign keys, naming
patterns). In a graph repo, the data _is_ the connections. The primitive
operations are link, unlink, and traverse — not put/get. You cannot meaningfully
map graph traversal onto keyed lookup without losing either the semantics or the
performance. Graphs gets its own behaviour because the structural pattern is
distinct: the libgraph implementation makes this concrete.

**Cmd** is the command pattern: validate, apply, reset. It represents operations
that are executed, not stored. There is no durable state, no key-value pair to
retrieve later. The resource is a command specification; the operation is its
execution. This matters for shell-driven workflows, infrastructure provisioning,
and anything where the side effect is the point. Cmd is in the repo tree because
it shares the five-verb surface — you can describe a command, observe its output
— but its extension behaviour is about execution lifecycle, not persistence.

**Batch** is write-behind buffering. Rather than flushing every write to the
backend immediately, Batch accumulates writes and flushes on a size threshold
or time interval. The primitive operations are push, flush, size, drain, and
status. This shape exists because the cost model for many backends (network I/O,
disk fsync, API rate limits) makes per-write flushing prohibitive at volume.
Batch decouples the write rate the caller sees from the write rate the backend
absorbs. The mem (GenServer) implementation supports configurable auto-flush;
the auto-flush logic lives in the implementation, not the behaviour.

**Column** is schema-enforced columnar storage. Rows must conform to a declared
schema; projections select subsets of columns. The extension callbacks add
create, put, select, delete, schema, count, and drop on top of the base five.
Column differs from Table in that the schema is part of the contract — you
cannot put an arbitrary term under a key, you put a row that validates against
declared column types. This gives you query semantics (select by column
predicate) and the ability to introspect the shape of stored data, not just its
presence. The ETS implementation keeps this in-process.

**Bus** (planned) is raw pub/sub transport. No struct opinions, no enrichment,
no logging. A message goes in on a topic, subscribers receive it. Bus is distinct
from the Events system (Section 3) precisely because Events is opinionated:
EventStruct, enrichment pipeline, telemetry hooks. Bus is the transport layer
underneath all of that — what you use when you need pub/sub without the event
machinery, or when you are building the event machinery itself.

**Queue** (planned) is ordered, durable, and ackable. The pattern is RabbitMQ or
Oban: messages are enqueued, workers dequeue and acknowledge, unacknowledged
messages are retried or dead-lettered. Queue differs from Batch in direction and
durability: Batch is write-behind for outbound I/O; Queue is a work-distribution
mechanism where delivery guarantees matter. Queue differs from Bus in that Bus
is fire-and-forget by design; Queue tracks delivery state per message.

**Stream** (planned) is append-only and replayable. The pattern is Kafka: events
are appended to a log, consumers read from an offset, old data is retained until
a retention policy expires it. Stream differs from Queue in that consumption is
non-destructive — multiple consumers can read the same data at different offsets
independently. It differs from Bus in that the log is durable: a consumer that
falls behind can catch up; a Bus subscriber that disconnects misses what it
missed.

**Merkel** (planned) is content-addressed and immutable. The pattern is Git or
IPFS: data is stored by a hash of its content, not by a mutable key. You cannot
update content under an address; you produce a new address for new content. This
shape exists for audit trails, content verification, and distributed sync where
you need to prove that what you received is what was sent. The address _is_ the
integrity check.

### Naming Convention

Behaviours live at `Comn.Repo.X`. Implementations live at
`Comn.Repo.X.Backend`. For example: `Comn.Repo.Table` is the behaviour;
`Comn.Repo.Table.ETS` is the ETS implementation. `Comn.Repo.File` is the
behaviour; `Comn.Repo.File.Local`, `Comn.Repo.File.NFS`, and
`Comn.Repo.File.IPFS` are the implementations. This keeps the module tree
readable: the behaviour is always one level up from its implementations, and
you can find all implementations of a shape by listing its namespace.

### NFS vs Local: A Design Choice

NFS wraps Local rather than reimplementing file I/O. The NFS implementation adds
exactly two things Local does not have: path resolution relative to a mount
point, and ESTALE detection. Everything else — reading, writing, streaming,
lifecycle state management — delegates to Local.

The path resolution difference is deliberate. NFS has a mount boundary to
enforce. `resolve_path/2` expands the path and validates that the result stays
within the mount point, rejecting traversal attempts (`../../etc/passwd` and
its variants). Local does not have a mount boundary. Local is deliberately "you
get what you ask for" — the path you pass is the path you get. If you are
exposing Local to untrusted input, path policy is your problem to add. The
library does not impose a sandbox on a shape that has no natural boundary;
doing so would be the wrong abstraction in the wrong place.

<a id="boot"></a>
## Supervision and Boot — How It Comes Alive

### The Boot Sequence

`Comn.Application.start/2` starts the supervision tree, then runs two discovery
passes in sequence:

```elixir
<!-- from lib/comn/application.ex -->
def start(_type, _args) do
  result = Comn.Supervisor.start_link()

  Comn.Errors.Registry.discover()
  Comn.Discovery.discover()

  result
end
```

The supervision tree brings up three children under a `one_for_one` strategy:

```elixir
<!-- from lib/comn/supervisor.ex -->
def init(_opts) do
  children = [
    {Registry, keys: :duplicate, name: Comn.EventBus},
    {Registry, keys: :duplicate, name: Comn.Events.Registry},
    Comn.EventLog
  ]

  Supervisor.init(children, strategy: :one_for_one)
end
```

`Comn.EventBus` and `Comn.Events.Registry` are both Registry processes with
`:duplicate` keys — multiple subscribers can register under the same topic.
`Comn.EventLog` is an Agent-backed append-only log. `one_for_one` means a crash
in `EventLog` does not take down the bus.

### Post-Supervision Discovery

Once the tree is up, two discovery passes run sequentially:

1. `Comn.Errors.Registry.discover/0` — scans all loaded modules for
   `__errors__/0`, collects every registered error code, and indexes the results
   into `persistent_term`. From this point forward, error lookups are a single
   read from shared memory.

2. `Comn.Discovery.discover/0` — scans for modules that export the four Comn
   callbacks (`look/0`, `recon/0`, `choices/0`, `act/1`), and indexes those into
   `persistent_term` as well.

### Why This Order Matters

The supervision tree must be up before discovery runs because `Comn.EventBus` is
a Registry process that other modules may reference during initialization. Start
discovery before the bus exists and you have a process lookup against nothing.

Error discovery runs before module discovery because module metadata — returned
by `recon/0` — may reference error codes. When `Discovery.discover/0` calls into
a module's `recon/0`, the error registry is already populated and those
references resolve cleanly.

### What's Not in the Tree

NATS and other external adapters are not supervised here. They require connection
configuration — broker addresses, credentials, TLS settings — that Comn cannot
know. They belong in the consumer application's supervision tree, started after
Comn's tree is up, with whatever configuration the consumer provides.

### Known Limitation: EventLog

`Comn.EventLog` is an Agent wrapping an ever-growing list. Appends are cheap;
the list grows without bound. This is acceptable for development, testing, and
low-volume audit scenarios. It is not suitable for production systems with
sustained event volume. A production deployment that needs durable event history
should route events to an external log and treat `EventLog` as a diagnostic
tool only.

### Closing the Arc

The system starts. The supervision tree comes up. Discovery runs and indexes
what exists into shared memory. From that point forward, any Comn module can be
found, queried, and operated through the same four verbs — regardless of where
it lives in the codebase or how it was registered. That is the design: uniform
introspection from boot to shutdown, with nothing requiring manual registration
and nothing hidden from the runtime.
