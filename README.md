# Comn

A shared Elixir foundation for building systems with uniform introspection, structured errors, event propagation, secrets management, and pluggable repository backends.

Every module implements `@behaviour Comn` — four callbacks (`look`, `recon`, `choices`, `act`) that make any subsystem discoverable and operable at runtime. You always know what a module is, what it can do, and how to use it.

## Status

**v0.6.1** — OTP application with supervision tree, compile-time error registry, automatic context enrichment, runtime module discovery, zone-based spatial addressing, and durable event streams (Mem, SQLite, NATS JetStream).

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
| Repo.Table | Complete | ETS key-value store |
| Repo.File | Complete | Local/NFS/IPFS file I/O |
| Repo.Graphs | Complete | libgraph-backed directed/undirected graphs; spatial verbs (`enter`/`exit`/`discover`/`traverse`) |
| Repo.Cmd | Complete | Command behaviour (Shell placeholder) |
| Repo.Batch | Complete | Buffered write-behind with auto-flush (Mem backend) |
| Repo.Column | Complete | Schema-enforced columnar storage with projections (ETS backend) |
| Repo.Bus | Planned | Raw pub/sub transport (no struct opinions) |
| Repo.Queue | Complete | Durable, crash-safe FIFO/LIFO job queues; backends: Mem (ETS), SQLite |
| Repo.Stream | Complete | Append-only, replayable event log; live subscribe; consumer groups; backends: Mem (ETS), SQLite, NATS JetStream |
| Repo.Merkel | Planned | Content-addressed, immutable (Git/IPFS pattern) |
| Infra | Placeholder | Not yet implemented |

## Requirements

- Elixir 1.20 or later
- Erlang/OTP 29 or later

The pinned toolchain is in `.tool-versions` (asdf / mise).

## Installation

```elixir
defp deps do
  [{:comn, path: "../comn"}]
end
```

The OTP application starts automatically — `Comn.Supervisor` brings up EventBus, Events.Registry, EventLog, and Presence, then discovers all registered error codes.

### Automated install

The installers are [Igniter](https://hexdocs.pm/igniter) tasks, so the host
project needs Igniter in its deps:

```elixir
{:igniter, "~> 0.8", only: [:dev, :test]}
```

Then, from inside a Phoenix app:

```bash
mix comn.install
```

This adds the dep, generates a `Comn.Contexts` boundary plug wired into your
router pipelines, and a starter error registry. Suppress pieces with
`--no-context-plug` / `--no-error-registry`.

To wire in both comn and the busybody dev directory in one shot:

```bash
mix comn.bootstrap
```

## The Comn Behaviour

Every module in the library implements `@behaviour Comn`:

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

Pluggable repository backends sharing a common `Comn.Repo` behaviour (`describe`, `get`, `set`, `delete`, `observe`). Each specialization adds its own callbacks.

### Tables (ETS)

```elixir
alias Comn.Repo.Table.ETS

{:ok, _} = ETS.create(:my_cache)
:ok = ETS.set(:my_cache, key: "user:1", value: %{name: "Ian"})
{:ok, %{name: "Ian"}} = ETS.get(:my_cache, key: "user:1")
{:ok, 1} = ETS.count(:my_cache)
:ok = ETS.drop(:my_cache)
```

### Files (Local, NFS, IPFS)

```elixir
alias Comn.Repo.File.Local

{:ok, fs} = Local.open("/tmp/example.txt", mode: [:read, :binary])
{:ok, fs} = Local.load(fs)
{:ok, data} = Local.read(fs)
Local.close(fs)
```

### Graphs (libgraph)

```elixir
alias Comn.Repo.Graphs.Graph

{:ok, g} = Graph.create(name: "deps", directed?: true)
{:ok, g} = Graph.link(g, :phoenix, :plug)
{:ok, g} = Graph.link(g, :plug, :cowboy)
{:ok, path} = Graph.traverse(g, type: :shortest_path, from: :phoenix, to: :cowboy)
#=> {:ok, [:phoenix, :plug, :cowboy]}
```

### Batch (buffered writes)

```elixir
alias Comn.Repo.Batch.Mem

{:ok, pid} = Mem.start_link(flush_fn: &IO.inspect/1, flush_interval: 5_000, max_buffer: 100)
:ok = Mem.push(pid, %{event: "page_view", ts: DateTime.utc_now()})
:ok = Mem.flush(pid)
```

### Column (schema-enforced columnar storage)

```elixir
alias Comn.Repo.Column.ETS

{:ok, ref} = ETS.create(:metrics, schema: %{ts: :integer, value: :float, host: :string})
:ok = ETS.put(ref, %{ts: 1713100800, value: 3.14, host: "web-1"})
{:ok, rows} = ETS.select(ref, where: [host: "web-1"], columns: [:ts, :value])
```

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

### Stream (append-only, replayable log)

```elixir
alias Comn.Repo.Stream.Mem
alias Comn.Events.EventStruct

:ok = Mem.create(:audit)
{:ok, 1} = Mem.append(:audit, EventStruct.new(:auth, "user.login", %{id: 1}))
{:ok, 2} = Mem.append(:audit, EventStruct.new(:auth, "user.logout", %{id: 1}))

{:ok, [{1, _}, {2, _}]} = Mem.read(:audit, :head, 10)   # first 10 (Unix head)
{:ok, [{2, _}]}         = Mem.read(:audit, 2, 10)       # from a caller-tracked offset
{:ok, 2}                = Mem.head(:audit)
```

Consumers track their own offsets. `delete/2` returns `repo.stream/append_only`.

Live delivery is a plain message. Subscribe first, then `read` from your last
offset to catch up, dropping any live message whose offset you already saw:

```elixir
{:ok, ref} = Mem.subscribe(:audit, [])
{:ok, 3} = Mem.append(:audit, EventStruct.new(:auth, "user.login", %{id: 2}))
receive do
  {:stream, :audit, 3, %EventStruct{topic: "user.login"}} -> :ok
end
:ok = Mem.unsubscribe(:audit, ref)
```

Consumer groups are a bookmark per group name, nothing more:

```elixir
{:ok, nil} = Mem.position(:audit, :billing)        # never committed: start from :head
{:ok, batch} = Mem.read(:audit, :head, 100)
{last, _} = List.last(batch)
:ok = Mem.commit(:audit, :billing, last)
{:ok, ^last} = Mem.position(:audit, :billing)      # next run reads from last + 1
```

The SQLite backend has the same API and survives restarts. Its process is not
linked to the opener; `close` keeps the file, `drop` deletes it:

```elixir
alias Comn.Repo.Stream.SQLite

:ok = SQLite.open(:audit, path: "/var/lib/app/audit.db")
{:ok, 1} = SQLite.append(:audit, EventStruct.new(:auth, "user.login", %{id: 1}))
:ok = SQLite.close(:audit)
:ok = SQLite.open(:audit, path: "/var/lib/app/audit.db")
{:ok, 1} = SQLite.head(:audit)

# or under a supervisor
children = [{SQLite, name: :audit, path: "/var/lib/app/audit.db"}]
```

The JetStream backend maps each stream to a NATS JetStream stream on subject
`comn.stream.<name>`; the offset is JetStream's own stream sequence. Group
positions live in the KV bucket `comn_stream_groups`. It needs a `Gnat`
connection:

```elixir
alias Comn.Repo.Stream.JetStream

{:ok, _} = Gnat.start_link(%{host: "127.0.0.1", port: 4222}, name: :gnat)
:ok = JetStream.open(:audit, conn: :gnat)
{:ok, seq} = JetStream.append(:audit, EventStruct.new(:auth, "user.login", %{id: 1}))
{:ok, [{^seq, _}]} = JetStream.read(:audit, :tail, 1)
:ok = JetStream.close(:audit)            # local process only; server stream kept
:ok = JetStream.drop(:audit)             # also deletes the server stream
```

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
alias Comn.Repo.Graphs.Graph

{:ok, g} = Graph.create()
{:ok, g} = Graph.link(g, :a, :b)
{:ok, g} = Graph.link(g, :b, :c)

zone = Comn.Zone.new(realm: :local, locale: "a")
{:ok, :a} = Graph.enter(g, zone)
{:ok, [:b]} = Graph.discover(g, zone)

# traverse/4 navigates and updates the calling process's context zone
{:ok, dest, [:a, :b, :c]} = Graph.traverse(g, zone, :c, [])
dest.locale  #=> "c"
```

Errors come back as registered codes: `repo.graph/zone_not_found`, `repo.graph/unreachable`.

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

  repo.ex                    Base repo behaviour (describe/get/set/delete/observe; optional enter/exit/discover)
  repo/table.ex              Table behaviour (create/drop/keys/count)
  repo/file.ex               File behaviour (open/load/stream/cast/read/write/close)
  repo/graphs.ex             Graph behaviour (link/unlink/traverse)
  repo/cmd.ex                Command behaviour (validate/apply/reset/enable/...)
  repo/batch.ex              Batch behaviour (push/flush/size/drain/status)
  repo/column.ex             Column behaviour (create/put/select/delete/schema/count/drop)
  repo/bus.ex                Bus behaviour (planned)
  repo/queue.ex              Queue facade (open/push/pop/peek/find/remove/close)
  repo/queue/backend.ex      Queue backend behaviour
  repo/queue/mem.ex          ETS queue backend
  repo/queue/sqlite.ex       SQLite queue backend
  repo/stream.ex             Stream behaviour (append/append_many/read/head/tail; optional subscribe/unsubscribe, commit/position)
  repo/stream/mem.ex         ETS stream backend
  repo/stream/sqlite.ex      SQLite durable stream backend (one GenServer per stream)
  repo/stream/jetstream.ex   NATS JetStream stream backend (offset = stream sequence)
  repo/merkel.ex             Merkel behaviour (planned)
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

  mix/tasks/comn.install.ex  Igniter installer (deps, Contexts plug, error registry)
  mix/tasks/comn.bootstrap.ex Igniter installer for comn + busybody together
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

## Documentation

```bash
mix docs                    # Builds HTML docs into doc/ via ex_doc
```

## License

AGPL-3.0
