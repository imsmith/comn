# Comn

A shared Elixir foundation for building systems with uniform introspection, structured errors, event propagation, secrets management, and pluggable repository backends.

Every module implements `@behaviour Comn` — four callbacks (`look`, `recon`, `choices`, `act`) that make any subsystem discoverable and operable at runtime. You always know what a module is, what it can do, and how to use it.

## Status

**v0.7.0** — OTP application with supervision tree, compile-time error registry, automatic context enrichment, runtime module discovery, zone-based spatial addressing, and nine Repo shapes that are all event sinks (ADR-0001) and all facades over one handle and one lifecycle: Table, Column, File, Graphs, Batch, Queue, Stream, Bus, Merkel. File paths are confined to a declared root. Three Credo checks ship with the library. See [CHANGELOG.md](CHANGELOG.md).

| Subsystem | Status | What it does |
|---|---|---|
| Comn | Complete | Universal `look`/`recon`/`choices`/`act` behaviour |
| Discovery | Complete | Runtime module indexing, type/behaviour queries |
| Supervisor | Complete | OTP supervisor for EventBus, EventLog, Events.Registry, Presence |
| Contexts | Complete | Process-scoped request context with automatic propagation; zone-aware |
| Zone | Complete | Structured spatial locator (`realm.region.locale`) |
| Presence | Complete | Zone-scoped actor presence (`announce`/`who`); Agent-backed local impl |
| Errors | Complete | Structured errors, categorization, compile-time registry with namespaced codes |
| Events | Complete | Registry-based pub/sub, event log, NATS adapter, structured events |
| Secrets | Complete | ChaCha20-Poly1305 local encryption + HashiCorp Vault Transit backend |
| Repo.Table | Complete | Key-value facade over fungible backends: ETS, Ecto |
| Repo.File | Complete | File facade with a lifecycle state machine; backends: Local, NFS, IPFS |
| Repo.Graphs | Complete | Graph facade (`link`/`unlink`/`traverse`) with spatial verbs; libgraph backend |
| Repo.Cmd | Complete | Command behaviour (Shell placeholder) |
| Repo.Batch | Complete | Buffered write-behind facade with auto-flush; Mem backend |
| Repo.Column | Complete | Schema-enforced columnar facade with projections; ETS backend |
| Repo.Bus | Complete | Publish a fact to every current subscriber, retain nothing; Registry backend |
| Repo.Queue | Complete | Durable, crash-safe FIFO/LIFO job queues; backends: Mem (ETS), SQLite |
| Repo.Stream | Complete | Append-only, replayable event log; live subscribe; one facade over Mem (ETS), SQLite, NATS JetStream |
| Repo.Merkel | Complete | Content-addressed, immutable, verifiable hash chain; backends: Mem (sha256), Git (bare repo) |
| Infra | Placeholder | Not yet implemented |

## Requirements

- Elixir 1.20 or later
- Erlang/OTP 29 or later
- Optional: `ecto_sql` (plus an adapter) for the `:ecto` table backend

The pinned toolchain is in `.tool-versions` (asdf / mise).

## Installation

```elixir
defp deps do
  [{:comn, path: "../comn"}]
end
```

The OTP application starts automatically — `Comn.Supervisor` brings up EventBus, Events.Registry, EventLog, and Presence, then discovers all registered error codes.

### Generator

From inside a Phoenix app that already has the dep:

```bash
mix comn.install
```

This creates a `Comn.Contexts` boundary plug and a starter error registry,
then prints the two lines you add by hand: the plug in your router
pipelines, and the dep if it is not there yet. Existing files are never
overwritten. Suppress pieces with `--no-context-plug` / `--no-error-registry`.

For the dev directory, add `busybody-client` separately; it is a
one-child-spec library with its own README.

## The Comn Behaviour

Every module in the library implements `@behaviour Comn`:

```elixir
Comn.Repo.look()
#=> "Repo — common I/O behaviour for data repositories (tables, files, graphs, commands)"

Comn.Repo.recon()
#=> %{callbacks: [:describe, :get, :set, :delete, :observe],
#     extensions: [Comn.Repo.Table, Comn.Repo.Column, Comn.Repo.File, Comn.Repo.Graphs,
#                  Comn.Repo.Batch, Comn.Repo.Queue, Comn.Repo.Bus, Comn.Repo.Stream,
#                  Comn.Repo.Merkel, Comn.Repo.Cmd],
#     type: :behaviour}

Comn.Repo.choices()
#=> %{extensions: ["Table", "Column", "File", "Graphs", "Batch", "Queue", "Bus", "Stream", "Merkel", "Cmd"],
#     implementations: ["Table.ETS", "Table.Ecto", "File.Local", ...]}

Comn.Repo.Table.act(%{action: :open, name: :my_table})
#=> {:ok, %Comn.Repo.Handle{shape: Comn.Repo.Table, backend: Comn.Repo.Table.ETSAdapter, ...}}
```

Behaviour-only modules return a `comn/behaviour_only` error from `act/1`. Placeholders return `comn/not_implemented`. An implementation given an input it does not recognise returns `comn/unknown_action`. All three are `Comn.Errors.ErrorStruct` values built by helpers on `Comn`.

### When to add it

Implement `@behaviour Comn` on modules that are **discoverable infrastructure** — behaviours, their implementations, and facade modules. If `Comn.Discovery.all()` should list it, add the behaviour. Don't add it to schemas, routers, controllers, helpers, or internal structs.

```elixir
defmodule MyApp.Repo.Postgres do
  @behaviour Comn
  @behaviour Comn.Repo

  @impl Comn
  def look, do: "Postgres — production database backend"
  # ...
end
```

### Runtime discovery

`Comn.Discovery` indexes all `@behaviour Comn` modules at boot:

```elixir
Comn.Discovery.all()
#=> [Comn.Repo, Comn.Repo.Table.ETS, MyApp.Repo.Postgres, ...]

Comn.Discovery.by_type(:implementation)
#=> [Comn.Repo.Table.ETS, Comn.Repo.File.Local, ...]

Comn.Discovery.implementations_of(Comn.Repo.File)
#=> [Comn.Repo.File.Local, Comn.Repo.File.NFS, Comn.Repo.File.IPFS]
```

## Contexts

Process-scoped request context. Set it once at the boundary; errors and events downstream auto-enrich from it.

```elixir
alias Comn.Contexts

ctx = Contexts.new(request_id: "req-123", user_id: "user-42")
Contexts.fetch(:request_id)  #=> "req-123"

Contexts.with_context(%{request_id: "req-456"}, fn ->
  Contexts.fetch(:request_id)  #=> "req-456"
end)
Contexts.fetch(:request_id)  #=> "req-123" (restored)
```

## Errors

All errors are `%Comn.Errors.ErrorStruct{}` with a namespaced `code` field. When a `Comn.Contexts` is active, errors auto-enrich with request IDs and trace IDs.

```elixir
alias Comn.Errors

{:ok, error} = Errors.wrap("something went wrong")
error = Errors.new(:validation, "email is required", :email)

Errors.categorize("invalid_format")    #=> :validation
Errors.categorize("database_timeout")  #=> :persistence
```

### Error registry

Declare error codes at compile time. Codes use `namespace/error_name` format, validated at compile time, duplicates rejected.

```elixir
defmodule MyApp.Auth.Errors do
  use Comn.Errors.Registry

  register_error "auth/invalid_token", :auth, message: "Token is invalid or expired", status: 401
  register_error "auth/forbidden",     :auth, message: "Insufficient permissions", status: 403
end

{:ok, err} = Comn.Errors.Registry.error("auth/invalid_token", field: "authorization")
{:error, Comn.Errors.Registry.error!("auth/invalid_token")}

Comn.Errors.Registry.http_status("auth/invalid_token")       #=> 401
Comn.Errors.Registry.codes_for_prefix("auth/")               #=> ["auth/forbidden", "auth/invalid_token"]
```

## Events

Registry-based pub/sub with an append-only event log. All processes started by `Comn.Supervisor`.

```elixir
Comn.EventBus.subscribe("user.created")

event = Comn.Events.EventStruct.new(:domain, "user.created", %{user_id: 42})
Comn.EventBus.broadcast("user.created", event)

event.id              #=> "a1b2c3d4-..."  (auto-generated UUID)
event.request_id      #=> from Comn.Contexts if set
event.correlation_id  #=> from Comn.Contexts if set

# Schema, version, and tags for routing and evolution
event = Comn.Events.EventStruct.new(:domain, "order.placed", %{id: 1}, MyApp.Orders,
  schema: "order.placed.v2", version: 2, tags: ["priority:high"])

# Event log for audit/replay
Comn.EventLog.record(event)
Comn.EventLog.all()
Comn.EventLog.for_topic("user.created")
```

NATS adapter is opt-in:

```elixir
children = [{Comn.Events.NATS, host: "nats.internal", port: 4222}]
```

## Secrets

Lock and unlock data with Ed25519 keys using ChaCha20-Poly1305 AEAD encryption.

```elixir
alias Comn.Secrets.{Local, Key}

{pub, priv} = :crypto.generate_key(:eddsa, :ed25519)

key = %Key{
  id: :crypto.hash(:blake2b, pub) |> binary_part(0, 16),
  algorithm: :ed25519,
  public: pub,
  private: priv
}

{:ok, locked} = Local.lock("sensitive data", key)
{:ok, "sensitive data"} = Local.unlock(locked, key)

{:ok, locked1} = Local.lock("secret 1", key)
{:ok, locked2} = Local.lock("secret 2", key)
{:ok, container} = Local.wrap([locked1, locked2], key)
{:ok, [^locked1, ^locked2]} = Local.unwrap(container, key)
```

The Vault backend (`Comn.Secrets.Vault`) delegates to HashiCorp Vault's Transit engine:

```elixir
key = %Key{
  algorithm: :ed25519,
  public: pub,
  private: priv,
  metadata: %{
    vault_addr: "http://localhost:8200",
    vault_token: System.get_env("VAULT_TOKEN"),
    vault_key_name: "my-transit-key"
  }
}
```

## Repo

### Every shape is an event sink

Every Repo shape accepts the same three canonical forms, so a caller can hand
a fact to a table, a file, a graph, a queue, or a stream without knowing which
it is ([ADR-0001](docs/adr/0001-every-repo-shape-is-an-event-sink.md)):

```elixir
alias Comn.Events.EventStruct
alias Comn.Repo.{Table, Queue, Stream}

fact = EventStruct.new(:domain, "order.placed", %{id: 1})

{:ok, t} = Table.open(:orders, backend: :ets)
:ok = Table.set(t, event: fact)                         # stored under fact.id
{:ok, ^fact} = Table.get(t, id: fact.id)
[^fact] = Table.observe(t, as: :events)

{:ok, q} = Queue.open("orders", backend: :mem)
:ok = Queue.set(q, event: fact)                         # enqueued
{:ok, ^fact} = Queue.get(q, id: fact.id)                # non-destructive

{:ok, s} = Stream.open(:orders_log, backend: :mem)
{:ok, _offset} = Stream.set(s, event: fact)                 # appended
[^fact] = Stream.observe(s, as: :events) |> Enum.to_list()
```

Anything `Comn.Event` can convert is an event by default, so
`set(h, event: %{type: :domain, topic: "order.placed", data: %{id: 1}})` and the
tuple form work on every shape too.

A file of events is a log (one encoded line per fact), a column store turns
the headers into columns, a graph makes the event a vertex keyed by its id.
The shared spec in `test/support/event_sink_conformance.ex` runs against every
backend; passing it is what makes a backend a Comn backend.

Pluggable repository backends sharing a common `Comn.Repo` behaviour (`describe`, `get`, `set`, `delete`, `observe`). Each specialization adds its own callbacks.

### Tables (ETS, Ecto)

```elixir
alias Comn.Repo.Table

{:ok, t} = Table.open(:my_cache, backend: :ets)
:ok = Table.set(t, "user:1", %{name: "Ian"})
{:ok, %{name: "Ian"}} = Table.get(t, "user:1")
{:ok, 1} = Table.count(t)
:ok = Table.drop(t)
```

`Comn.Repo.Table.ETS` keeps its direct surface (`create`/`set`/`get`/`drop`)
for existing callers; new code goes through the facade so the backend is a
word in one option.

The `:ecto` backend works on any Ecto adapter and holds to four rules. The
repository is configuration, not a module Comn knows about. Every mutation
is against a schema, the default being the event itself. There are no
migrations: the schema module is the declaration and the database is
converged to it on first use. And every mutation is a saga: a transaction
with an upsert, followed by a system event on `Comn.EventBus` saying
whether it committed or rolled back.

```elixir
{:ok, t} = Table.open(:sessions, backend: :ecto,
  ecto: [adapter: Ecto.Adapters.SQLite3, database: "/var/lib/app/kv.db"])
# ecto: "config/repo.exs" (a file returning that keyword) or repo: MyApp.Repo also work

:ok = Table.set(t, :k, %{any: :term})                      # default schema: the event, table comn_sessions
{:ok, %{any: :term}} = Table.get(t, :k)

fact = EventStruct.new(:domain, "session.opened", %{user: "ian", count: 1})
:ok = Table.set(t, [event: fact], schema: MyApp.SessionRow) # cast + upsert on the pk
{:ok, %MyApp.SessionRow{user: "ian"}} = Table.get(t, fact.id, schema: MyApp.SessionRow)

Comn.EventBus.subscribe("comn.repo.table")                  # repo.table.set / .delete, status :ok | :failed
```

`ecto_sql` is an optional dependency; without it the `:ecto` backend is
simply absent from `Table.open/2`.

### Files (Local, NFS, IPFS)

A file is a value with a state, so `load` and `write` return a new handle.
Every path is confined to a declared root (`root:` for local, `mount:` for
NFS); a path that resolves outside it is `repo.file/outside_root`.

```elixir
alias Comn.Repo.File

{:ok, f} = File.open("example.txt", backend: :local, root: "/srv/data", mode: [:read, :binary])
{:ok, f} = File.load(f)
{:ok, data} = File.read(f)
File.close(f)

{:ok, f} = File.open("notes.txt", backend: :nfs, mount: "/mnt/share")
{:ok, f} = File.open("Qm...", backend: :ipfs, api: "http://localhost:5001")
```

### Graphs (libgraph)

A graph is a value, so `link`, `unlink`, `set`, and `delete` return a new handle.

```elixir
alias Comn.Repo.Graphs

{:ok, g} = Graphs.open("deps", directed?: true)
{:ok, g} = Graphs.link(g, :phoenix, :plug)
{:ok, g} = Graphs.link(g, :plug, :cowboy)
{:ok, path} = Graphs.traverse(g, type: :shortest_path, from: :phoenix, to: :cowboy)
#=> {:ok, [:phoenix, :plug, :cowboy]}
```

### Batch (buffered writes)

`close/1` flushes before releasing; `drop/1` discards the buffer.

```elixir
alias Comn.Repo.Batch

{:ok, b} = Batch.open(:page_views, max_size: 100, interval_ms: 5_000, on_flush: &IO.inspect/1)
:ok = Batch.add(b, %{event: "page_view", ts: DateTime.utc_now()})
{:ok, 1} = Batch.flush(b)
Batch.close(b)
```

### Column (schema-enforced columnar storage)

```elixir
alias Comn.Repo.Column

{:ok, c} = Column.open(:metrics, schema: %{ts: :integer, value: :float, host: :string})
:ok = Column.append_row(c, %{ts: 1713100800, value: 3.14, host: "web-1"})
{:ok, rows} = Column.project(c, [:ts, :value], %{host: "web-1"})
Column.drop(c)
```

Every facade above, and Table, Queue, Bus, Stream, and Merkel, shares one
`Comn.Repo.Handle` and one `Comn.Repo.Lifecycle` (`open`/`close`/`drop`,
backend resolution). The older implementation modules (`Comn.Repo.File.Local`,
`Comn.Repo.Graphs.Graph`, `Comn.Repo.Batch.Mem`, `Comn.Repo.Column.ETS`) keep
their public surface and sit behind private adapters.

### Queue (durable, ackable jobs)

```elixir
alias Comn.Repo.Queue

{:ok, q} = Queue.open("jobs", backend: :mem, discipline: :fifo)
:ok = Queue.push(q, %{n: 1})
[%{n: 1}] = Queue.peek(q, 1)

# pop/2 runs the callback; if it raises or the caller dies the item is requeued
{:ok, :done} = Queue.pop(q, fn %{n: _} -> :done end)
:empty = Queue.pop(q, & &1)

# SQLite backend survives restarts
{:ok, q} = Queue.open("jobs", backend: :sqlite, path: "/var/lib/app/jobs.queue")
```

### Bus (publish to everyone listening, retain nothing)

```elixir
alias Comn.Repo.Bus

{:ok, b} = Bus.open(:notifications)                      # backend: :registry
{:ok, ref} = Bus.subscribe(b, topic: "order.placed")      # topic: is optional
:ok = Bus.publish(b, EventStruct.new(:domain, "order.placed", %{id: 1}))
receive do
  {:bus, :notifications, %EventStruct{data: %{id: 1}}} -> :ok
end
:ok = Bus.unsubscribe(b, ref)

Bus.observe(b, as: :events) |> Enum.take(1)               # a live stream
```

`get` and `delete` return `repo.bus/not_retained`: a bus keeps nothing.

### Stream (append-only, replayable log)

One facade, three backends. The backend is a word in one option and the
calling code is otherwise identical:

```elixir
alias Comn.Repo.Stream
alias Comn.Events.EventStruct

{:ok, s} = Stream.open(:audit, backend: :mem)
# {:ok, s} = Stream.open(:audit, backend: :sqlite, path: "/var/lib/app/audit.db")
# {:ok, s} = Stream.open(:audit, backend: :jetstream, conn: :gnat)

{:ok, 1} = Stream.append(s, EventStruct.new(:auth, "user.login", %{id: 1}))
{:ok, 2} = Stream.append(s, EventStruct.new(:auth, "user.logout", %{id: 1}))

{:ok, [{1, _}, {2, _}]} = Stream.read(s, :head, 10)   # first 10 (Unix head)
{:ok, [{2, _}]}         = Stream.read(s, 2, 10)       # forward from a caller-tracked offset
{:ok, 2}                = Stream.head(s)              # latest offset
{:ok, 1}                = Stream.tail(s)              # earliest offset
```

Consumers track their own offsets. `delete/2` returns `repo.stream/append_only`.

Live delivery is a plain message. Subscribe first, then `read` from your last
offset to catch up, dropping any live message whose offset you already saw:

```elixir
{:ok, ref} = Stream.subscribe(s)
{:ok, 3} = Stream.append(s, EventStruct.new(:auth, "user.login", %{id: 2}))
receive do
  {:stream, :audit, 3, %EventStruct{topic: "user.login"}} -> :ok
end
:ok = Stream.unsubscribe(s, ref)
```

Lifecycle: `close/1` releases the handle and a durable backend keeps its data;
`drop/1` deletes the stream. A durable stream under a supervisor:

```elixir
children = [{Comn.Repo.Stream, name: :audit, backend: :sqlite, path: "/var/lib/app/audit.db"}]
```

The `:jetstream` backend maps each stream to a NATS JetStream stream on subject
`comn.stream.<name>`; the offset is JetStream's own stream sequence. It needs a
running `Gnat` connection passed as `conn:`.

### Merkel (content-addressed, immutable, verifiable)

Four verbs: `put` returns a content address, `get` returns what is behind one,
`head` is the root, `verify` walks root to genesis recomputing every hash.
Every put extends a hash chain, so the root commits to everything before it.

```elixir
alias Comn.Repo.Merkel

{:ok, m} = Merkel.open(:audit_chain, backend: :mem)
# {:ok, m} = Merkel.open(:audit_chain, backend: :git, path: "/var/lib/app/audit.git")

{:ok, a1} = Merkel.put(m, EventStruct.new(:auth, "user.login", %{id: 1}))
{:ok, a2} = Merkel.put(m, %{type: :auth, topic: "user.logout", data: %{id: 1}})
{:ok, %EventStruct{topic: "user.logout"}} = Merkel.get(m, a2)
{:ok, %Merkel.Node{parent: ^a1}} = Merkel.node(m, a2)
{:ok, ^a2} = Merkel.head(m)                       # publish or sign this
:ok = Merkel.verify(m)                            # or {:error, repo.merkel/tampered} naming the address
```

The `:git` backend makes each put a commit on a bare repository; the address
is the commit id and git itself refuses to read a corrupted object. The bytes
that get hashed come from the `Comn.Merkel` protocol, so a type can define a
portable canonical form; the default is Erlang's deterministic term format.

## Spatial

A `Comn.Zone` is a structured locator — `realm.region.locale` — used as ambient context and as a spatial address for repos that have a notion of place.

```elixir
zone = Comn.Zone.new(realm: :mesh, region: "home", locale: "kitchen")
Comn.Zone.to_string(zone)         #=> "mesh.home.kitchen"
Comn.Zone.parse("cluster.us-east") #=> {:ok, %Comn.Zone{realm: :cluster, region: "us-east"}}
```

`Comn.Contexts` defaults its `:zone` to `Comn.Zone.local()` and accepts a string for backwards compatibility (auto-parsed).

### Presence (zone-scoped actors)

```elixir
zone = Comn.Zone.new(realm: :local, locale: "lobby")
:ok = Comn.Presence.announce(zone, "alice", :here)
{:ok, [{"alice", :here}]} = Comn.Presence.who(zone)
:ok = Comn.Presence.announce(zone, "alice", :gone)
```

### Spatial verbs on Repo

`Comn.Repo` defines three optional callbacks — `enter/2`, `exit/2`, `discover/2` — keyed by a zone. Repos with a notion of place implement them; flat repos (ETS, blob stores) do not.

```elixir
alias Comn.Repo.Graphs

{:ok, g} = Graphs.open("rooms")
{:ok, g} = Graphs.link(g, :a, :b)
{:ok, g} = Graphs.link(g, :b, :c)

zone = Comn.Zone.new(realm: :local, locale: "a")
{:ok, :a} = Graphs.enter(g, zone)
{:ok, [:b]} = Graphs.discover(g, zone)

# traverse/4 navigates and updates the calling process's context zone
{:ok, dest, [:a, :b, :c]} = Graphs.traverse(g, zone, :c, [])
dest.locale  #=> "c"
```

Errors come back as registered codes: `repo.graphs/zone_not_found`, `repo.graphs/unreachable`.

## Architecture

```text
lib/comn/
  comn.ex                    Comn behaviour (look/recon/choices/act)
  application.ex             OTP application callback
  supervisor.ex              OTP supervisor (EventBus, Events.Registry, EventLog, Presence)
  discovery.ex               Runtime module discovery and indexing
  zone.ex                    Structured spatial locator (realm.region.locale)
  presence.ex                Zone-scoped actor presence behaviour + Agent backend

  contexts.ex                Process-scoped context management
  contexts/context_struct.ex Context data struct
  contexts/policy_struct.ex  Policy data struct
  contexts/rule_struct.ex    Rule data struct

  errors.ex                  Error wrapping and categorization
  errors/error_struct.ex     Error data struct
  errors/registry.ex         Compile-time error code registry
  errors/impl/               Error protocol implementations

  credo/check.ex             Shared AST walk for the Credo checks below
  credo/bare_error_atom.ex   Credo: every error is an ErrorStruct
  credo/secret_from_env.ex   Credo: secrets do not come from env/config
  credo/raw_shell.ex         Credo: process execution goes through Repo.Cmd

  merkel.ex                  Comn.Merkel protocol: canonical bytes of a term
  events.ex                  Pub/sub behaviour
  events/event_bus.ex        Registry-based pub/sub
  events/event_log.ex        Agent-based append-only event log
  events/event_struct.ex     Event data struct
  events/nats.ex             NATS adapter (named process, opt-in)
  events/registry.ex         Registry adapter
  events/errors.ex           Events subsystem error codes
  events/impl/               Event protocol implementations

  secrets.ex                 Secrets behaviour
  secrets/local.ex           ChaCha20-Poly1305 local encryption
  secrets/vault.ex           HashiCorp Vault Transit backend
  secrets/key.ex             Cryptographic key struct
  secrets/locked_blob.ex     Encrypted blob struct
  secrets/container.ex       Blob container struct
  secrets/errors.ex          Secrets subsystem error codes
  secrets/utils.ex           Key validation and container wrap/unwrap shared by backends

  repo.ex                    Base repo behaviour (describe/get/set/delete/observe; optional enter/exit/discover; backends/0)
  repo/handle.ex             One opaque handle for every shape (shape, backend, state, name, meta)
  repo/lifecycle.ex          open/close/drop and backend resolution shared by every facade
  repo/table.ex              Table facade (open/close/drop/get/set/delete/keys/count) + direct-backend behaviour
  repo/table/backend.ex      Private backend contract
  repo/table/ets_adapter.ex  Backend contract over Table.ETS
  repo/table/ecto.ex         Ecto backend: sagas, schema-directed upserts, converge instead of migrate
  repo/table/ecto/event_row.ex  Default schema: the event as a row
  repo/table/ecto/term.ex    Ecto type storing any term faithfully
  repo/table/ecto/repos.ex   Repository from configuration (keyword, .exs file, or module)
  repo/file.ex               File facade (open/close/drop/load/stream/cast/read/write) + direct-backend behaviour
  repo/file/backend.ex       Private backend contract
  repo/file/adapter.ex       Backend contract over Local, NFS, and IPFS
  repo/file/root.ex          Path confinement: every file path resolves under a declared root
  repo/graphs.ex             Graphs facade (open/close/drop/link/unlink/traverse; spatial verbs) + direct-backend behaviour
  repo/graphs/backend.ex     Private backend contract
  repo/graphs/graph_adapter.ex  Backend contract over Graphs.Graph
  repo/cmd.ex                Command behaviour (validate/apply/reset/enable/...)
  repo/batch.ex              Batch facade (open/close/drop/add/add_many/flush/pending/config) + direct-backend behaviour
  repo/batch/backend.ex      Private backend contract
  repo/batch/mem_adapter.ex  Backend contract over Batch.Mem
  repo/column.ex             Column facade (open/close/drop/define_schema/append_row/project/count) + direct-backend behaviour
  repo/column/backend.ex     Private backend contract
  repo/column/ets_adapter.ex Backend contract over Column.ETS
  repo/bus.ex                Bus facade (open/close/drop/publish/subscribe/unsubscribe)
  repo/bus/backend.ex        Private backend contract
  repo/bus/registry.ex       Local Registry backend
  repo/queue.ex              Queue facade (open/push/pop/peek/find/remove/close)
  repo/queue/backend.ex      Queue backend behaviour
  repo/queue/mem.ex          ETS queue backend
  repo/queue/sqlite.ex       SQLite queue backend
  repo/stream.ex             Stream facade (open/close/drop/append/read/head/tail/subscribe)
  repo/stream/backend.ex     Private backend contract
  repo/stream/mem.ex         ETS backend
  repo/stream/sqlite.ex      SQLite durable backend (one GenServer per stream)
  repo/stream/jetstream.ex   NATS JetStream backend (offset = stream sequence)
  repo/merkel.ex             Merkel facade (open/close/drop/put/get/node/head/verify)
  repo/merkel/node.ex        One link of the chain (address, parent, content hashes)
  repo/merkel/backend.ex     Private backend contract
  repo/merkel/mem.ex         ETS backend, sha256 addresses
  repo/merkel/git.ex         Bare git repository backend, commit ids as addresses
  repo/merkel/github.ex      (empty; a remote chain over the API, when a consumer needs it)
  repo/table/ets.ex          ETS key-value implementation
  repo/file/local.ex         Local filesystem implementation
  repo/file/nfs.ex           NFS mount-point wrapper
  repo/file/ipfs.ex          IPFS daemon API backend
  repo/graphs/graph.ex       libgraph implementation
  repo/cmd/shell.ex          Shell command execution (placeholder)
  repo/batch/mem.ex          In-memory GenServer with auto-flush
  repo/column/ets.ex         ETS columnar implementation
  repo/actor.ex              Actor-style repo (placeholder)
  repo/errors.ex             Repo subsystem error codes

  infra.ex                   Infrastructure management (placeholder)

  mix/tasks/comn.install.ex  Generator for the Contexts plug and error registry
```

## Running Tests

```bash
mix test                    # All tests (Vault tests auto-excluded)
VAULT_TOKEN=xxx mix test    # Include Vault integration tests
NATS_URL=nats://127.0.0.1:4222 mix test   # Include JetStream tests (needs a -js server)
```

A throwaway JetStream server for the tests:

```bash
podman run -d --name comn-nats -p 4222:4222 docker.io/library/nats:latest -js
```

Every `iex>` example in a moduledoc or function doc is a doctest and runs
with the suite (`test/doctest_test.exs` plus per-module test files).

## Quality gates

```bash
mix credo --strict          # style and the three Comn doctrine checks; clean, tests included
mix sobelow                 # security static analysis; 13 low traversal findings, see CHANGELOG
mix deps.audit              # known vulnerabilities in dependencies (mix_audit)
mix vet.check               # dependency owner, age, and typosquat check before deps.get
mix vet --skip-hex          # static scan of dependency source (vet_cli)
```

Analyzer findings are fixed in code, not suppressed. Where a check cannot
be satisfied by any correct code, the count is stated in the CHANGELOG.

## Documentation

```bash
mix docs                    # Builds HTML docs into doc/ via ex_doc
```

Release notes are in [CHANGELOG.md](CHANGELOG.md). The design rationale is
[guides/design.md](guides/design.md); decisions are under `docs/adr/`.

## License

AGPL-3.0
