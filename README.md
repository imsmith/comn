# Comn

Shared Elixir foundation providing standardized abstractions for error handling, event systems, secrets management, repository access, and request context propagation.

## Status

**v0.5.0** — OTP application with supervision tree. All modules implement `@behaviour Comn` for uniform introspection. Structured error codes via compile-time registry. Automatic context enrichment on errors and events.

| Subsystem | Status | Description |
|---|---|---|
| **Comn** | Complete | Universal `look`/`recon`/`choices`/`act` behaviour |
| **Discovery** | Complete | Runtime module indexing, type/behaviour queries |
| **Supervisor** | Complete | OTP supervisor for EventBus, EventLog, Events.Registry |
| **Secrets** | Complete | ChaCha20-Poly1305 local encryption + HashiCorp Vault Transit backend |
| **Events** | Complete | Registry-based pub/sub, Agent-based log, NATS adapter, structured events with schema/version/tags |
| **Errors** | Complete | Error protocol, categorization, compile-time registry with namespaced codes, context enrichment |
| **Contexts** | Complete | Process-scoped request context with automatic propagation to errors and events |
| **Repo** | Working | ETS key-value, local/NFS/IPFS file I/O, libgraph graphs, Cmd behaviour |
| **Infra** | Placeholder | Not yet implemented |

## Installation

Add Comn as a dependency. The OTP application starts automatically — `Comn.Supervisor` brings up EventBus, EventLog, and Events.Registry, then discovers all error codes.

```elixir
defp deps do
  [
    {:comn, path: "../comn"}
  ]
end
```

## The Comn Behaviour

Every module in the library implements `@behaviour Comn`, providing four callbacks for discovery and action:

```elixir
# What is this?
Comn.Repo.look()
#=> "Repo — common I/O behaviour for data repositories (tables, files, graphs, commands)"

# What can it do?
Comn.Repo.recon()
#=> %{callbacks: [:describe, :get, :set, :delete, :observe],
#     extensions: [Comn.Repo.Table, Comn.Repo.File, Comn.Repo.Graphs, Comn.Repo.Cmd],
#     type: :behaviour}

# What are my options?
Comn.Repo.choices()
#=> %{extensions: ["Table", "File", "Graphs", "Cmd"],
#     implementations: ["Table.ETS", "File.Local", ...]}

# Do it
Comn.Repo.Table.ETS.act(%{action: :create, name: :my_table})
#=> {:ok, #Reference<...>}
```

Behaviour-only modules return `{:error, :behaviour_only}` from `act/1`. Unimplemented placeholders return `{:error, :not_implemented}`.

### When to implement `@behaviour Comn`

Implement it on modules that are **discoverable infrastructure**: behaviours,
their implementations, and facade modules that orchestrate them. These are
the modules that answer "what can this system do?"

```elixir
defmodule MyApp.Repo.Postgres do
  @behaviour Comn
  @behaviour Comn.Repo

  @impl Comn
  def look, do: "Postgres — production database backend"
  # ...
end
```

Don't implement it on schemas, routers, controllers, helpers, or internal
structs. The litmus test: if `Comn.Discovery.all()` should list it, add
the behaviour. If not, skip it.

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

## Usage

### Secrets

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

# Wrap multiple locked blobs into a single encrypted container
{:ok, locked1} = Local.lock("secret 1", key)
{:ok, locked2} = Local.lock("secret 2", key)
{:ok, container} = Local.wrap([locked1, locked2], key)
{:ok, [^locked1, ^locked2]} = Local.unwrap(container, key)
```

The Vault backend (`Comn.Secrets.Vault`) uses the same `Comn.Secrets` behaviour but delegates to HashiCorp Vault's Transit engine:

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

### Events

Pub/sub via Registry and an append-only event log. All event processes are
started by `Comn.Supervisor` — no manual setup needed.

```elixir
# Subscribe and broadcast
Comn.EventBus.subscribe("user.created")

event = Comn.Events.EventStruct.new(:domain, "user.created", %{user_id: 42})
Comn.EventBus.broadcast("user.created", event)

# Events auto-enrich with ambient context
event.id              #=> "a1b2c3d4-..."  (auto-generated UUID)
event.request_id      #=> pulled from Comn.Contexts if set
event.correlation_id  #=> pulled from Comn.Contexts if set

# Schema, version, and tags for routing and evolution
event = Comn.Events.EventStruct.new(:domain, "order.placed", %{id: 1}, MyApp.Orders,
  schema: "order.placed.v2", version: 2, tags: ["priority:high"])

# Event log for audit/replay
Comn.EventLog.record(event)
Comn.EventLog.all()
Comn.EventLog.for_topic("user.created")
```

NATS adapter is opt-in — add to your own supervision tree:

```elixir
children = [
  {Comn.Events.NATS, host: "nats.internal", port: 4222}
]
```

### Errors

All errors are `%Comn.Errors.ErrorStruct{}` with a namespaced `code` field.
Errors are automatically enriched with ambient context (request IDs, trace
IDs) when a `Comn.Contexts` is set on the calling process.

```elixir
alias Comn.Errors

# Wrap a term — returns {:ok, %ErrorStruct{}} | {:error, reason}
{:ok, error} = Errors.wrap("something went wrong")

# Create categorized errors (returns %ErrorStruct{} directly)
error = Errors.new(:validation, "email is required", :email)

# Auto-categorize from reason strings
Errors.categorize("invalid_format")    #=> :validation
Errors.categorize("database_timeout")  #=> :persistence
Errors.categorize("connection_refused") #=> :network

# Context auto-enrichment — set context once at the boundary
Comn.Contexts.new(request_id: "req-123", trace_id: "trace-456")
{:ok, error} = Errors.wrap("timeout")
error.request_id  #=> "req-123"
error.trace_id    #=> "trace-456"
```

### Error Registry

Declare error codes at compile time with enforced `namespace/error_name`
format. Codes are validated at compile time, duplicates rejected at
registration time. All Comn modules register their error codes.

```elixir
# Declare errors in a module
defmodule MyApp.Auth.Errors do
  use Comn.Errors.Registry

  register_error "auth/invalid_token",  :auth, message: "Token is invalid or expired", status: 401
  register_error "auth/forbidden",      :auth, message: "Insufficient permissions", status: 403
end

# Create errors from codes (auto-enriched with ambient context)
{:ok, err} = Comn.Errors.Registry.error("auth/invalid_token", field: "authorization")
err.code     #=> "auth/invalid_token"
err.message  #=> "Token is invalid or expired"

# Or get the struct directly for {:error, ...} tuples
{:error, Comn.Errors.Registry.error!("auth/invalid_token")}

# HTTP status mapping
Comn.Errors.Registry.http_status("auth/invalid_token")  #=> 401

# Query by prefix or category
Comn.Errors.Registry.codes_for_prefix("auth/")  #=> ["auth/forbidden", "auth/invalid_token"]
Comn.Errors.Registry.codes_for(:auth)            #=> ["auth/forbidden", "auth/invalid_token"]
```

### Contexts

Process-scoped request context for propagating metadata. Set once at the
boundary; errors and events downstream auto-enrich from it.

```elixir
alias Comn.Contexts

ctx = Contexts.new(request_id: "req-123", user_id: "user-42")
Contexts.fetch(:request_id)  #=> "req-123"

# Temporary context scope
Contexts.with_context(%{request_id: "req-456"}, fn ->
  Contexts.fetch(:request_id)  #=> "req-456"
end)
Contexts.fetch(:request_id)  #=> "req-123" (restored)
```

### Repo — Tables (ETS)

```elixir
alias Comn.Repo.Table.ETS

{:ok, _} = ETS.create(:my_cache)
:ok = ETS.set(:my_cache, key: "user:1", value: %{name: "Ian"})
{:ok, %{name: "Ian"}} = ETS.get(:my_cache, key: "user:1")
{:ok, 1} = ETS.count(:my_cache)
:ok = ETS.drop(:my_cache)
```

### Repo — Files (Local, NFS, IPFS)

```elixir
alias Comn.Repo.File.Local

{:ok, fs} = Local.open("/tmp/example.txt", mode: [:read, :binary])
{:ok, fs} = Local.load(fs)
{:ok, data} = Local.read(fs)
Local.close(fs)
```

### Repo — Graphs (libgraph)

```elixir
alias Comn.Repo.Graphs.Graph

{:ok, g} = Graph.create(name: "deps", directed?: true)
{:ok, g} = Graph.link(g, :phoenix, :plug)
{:ok, g} = Graph.link(g, :plug, :cowboy)
{:ok, path} = Graph.traverse(g, type: :shortest_path, from: :phoenix, to: :cowboy)
#=> {:ok, [:phoenix, :plug, :cowboy]}
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
  repo/table/ets.ex          ETS implementation
  repo/file/local.ex         Local filesystem implementation
  repo/file/nfs.ex           NFS mount-point wrapper
  repo/file/ipfs.ex          IPFS daemon API backend
  repo/graphs/graph.ex       libgraph implementation
  repo/cmd/shell.ex          Shell command execution (placeholder)
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
