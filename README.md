# Comn

A shared Elixir foundation for building systems with uniform introspection, structured errors, event propagation, secrets management, and pluggable repository backends.

Every module implements `@behaviour Comn` — four callbacks (`look`, `recon`, `choices`, `act`) that make any subsystem discoverable and operable at runtime. You always know what a module is, what it can do, and how to use it.

## Status

**v0.5.0** — OTP application with supervision tree, compile-time error registry, automatic context enrichment, and runtime module discovery.

| Subsystem | Status | What it does |
|---|---|---|
| Comn | Complete | Universal `look`/`recon`/`choices`/`act` behaviour |
| Discovery | Complete | Runtime module indexing, type/behaviour queries |
| Supervisor | Complete | OTP supervisor for EventBus, EventLog, Events.Registry |
| Contexts | Complete | Process-scoped request context with automatic propagation |
| Errors | Complete | Structured errors, categorization, compile-time registry with namespaced codes |
| Events | Complete | Registry-based pub/sub, event log, NATS adapter, structured events |
| Secrets | Complete | ChaCha20-Poly1305 local encryption + HashiCorp Vault Transit backend |
| Repo.Table | Complete | ETS key-value store |
| Repo.File | Complete | Local/NFS/IPFS file I/O |
| Repo.Graphs | Complete | libgraph-backed directed/undirected graphs |
| Repo.Cmd | Complete | Command behaviour (Shell placeholder) |
| Repo.Batch | Complete | Buffered write-behind with auto-flush (Mem backend) |
| Repo.Column | Complete | Schema-enforced columnar storage with projections (ETS backend) |
| Repo.Bus | Planned | Raw pub/sub transport (no struct opinions) |
| Repo.Queue | Planned | Ordered, durable, ackable (RabbitMQ/Oban pattern) |
| Repo.Stream | Planned | Append-only, replayable (Kafka pattern) |
| Repo.Merkel | Planned | Content-addressed, immutable (Git/IPFS pattern) |
| Infra | Placeholder | Not yet implemented |

## Installation

```elixir
defp deps do
  [{:comn, path: "../comn"}]
end
```

The OTP application starts automatically — `Comn.Supervisor` brings up EventBus, EventLog, and Events.Registry, then discovers all registered error codes.

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

Behaviour-only modules return `{:error, :behaviour_only}` from `act/1`. Placeholders return `{:error, :not_implemented}`.

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

## Architecture

```text
lib/comn/
  comn.ex                    Comn behaviour (look/recon/choices/act)
  application.ex             OTP application callback
  supervisor.ex              OTP supervisor (EventBus, EventLog, Events.Registry)
  discovery.ex               Runtime module discovery and indexing

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

  repo.ex                    Base repo behaviour (describe/get/set/delete/observe)
  repo/table.ex              Table behaviour (create/drop/keys/count)
  repo/file.ex               File behaviour (open/load/stream/cast/read/write/close)
  repo/graphs.ex             Graph behaviour (link/unlink/traverse)
  repo/cmd.ex                Command behaviour (validate/apply/reset/enable/...)
  repo/batch.ex              Batch behaviour (push/flush/size/drain/status)
  repo/column.ex             Column behaviour (create/put/select/delete/schema/count/drop)
  repo/bus.ex                Bus behaviour (planned)
  repo/queue.ex              Queue behaviour (planned)
  repo/stream.ex             Stream behaviour (planned)
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
```

## Running Tests

```bash
mix test                    # All tests (Vault tests auto-excluded)
VAULT_TOKEN=xxx mix test    # Include Vault integration tests
```

## License

AGPL-3.0
