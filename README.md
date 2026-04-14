# Comn

Shared Elixir foundation providing standardized abstractions for error handling, event systems, secrets management, repository access, and request context propagation.

## Status

**v0.4.0** — Single app (no longer an umbrella). All modules implement the `Comn` behaviour for uniform introspection.

| Subsystem | Status | Description |
|---|---|---|
| **Comn** | Complete | Universal `look`/`recon`/`choices`/`act` behaviour |
| **Secrets** | Complete | ChaCha20-Poly1305 local encryption + HashiCorp Vault Transit backend |
| **Events** | Working | Registry-based pub/sub (EventBus), Agent-based log (EventLog), NATS adapter |
| **Errors** | Working | Error protocol, categorization, wrapping for strings/atoms/maps |
| **Contexts** | Working | Process-scoped request context with propagation |
| **Repo** | Working | ETS key-value, local/NFS/IPFS file I/O, libgraph graphs, Cmd behaviour |
| **Infra** | Placeholder | Not yet implemented |

## Installation

Add Comn as a path dependency:

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

## Usage

### Secrets

Lock and unlock data with Ed25519 keys using ChaCha20-Poly1305 AEAD encryption.

```elixir
alias Comn.Secrets.{Local, Key}

# Generate a key pair
{pub, priv} = :crypto.generate_key(:eddsa, :ed25519)

key = %Key{
  id: :crypto.hash(:blake2b, pub) |> binary_part(0, 16),
  algorithm: :ed25519,
  public: pub,
  private: priv
}

# Lock (encrypt) and unlock (decrypt)
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

Pub/sub via Registry and an append-only event log.

```elixir
# Start the bus (add to your supervision tree)
Registry.start_link(keys: :duplicate, name: Comn.EventBus)

# Subscribe and broadcast
Comn.EventBus.subscribe("user.created")

event = Comn.Events.EventStruct.new("user.created", :domain, %{user_id: 42})
Comn.EventBus.broadcast("user.created", event)

# Receive in subscribing process
receive do
  {:event, "user.created", ^event} -> :ok
end

# Event log for audit/replay
{:ok, _} = Comn.EventLog.start_link([])
Comn.EventLog.record(event)
Comn.EventLog.all()
Comn.EventLog.for_topic("user.created")
```

### Errors

Wrap arbitrary terms into structured errors with categorization.

```elixir
alias Comn.Errors

# Wrap a string into an ErrorStruct
error = Errors.wrap("something went wrong")

# Create categorized errors
error = Errors.new(:validation, "email is required", :email)
error = Errors.new(:persistence, "connection timeout")

# Auto-categorize from reason strings
Errors.categorize("invalid_format")    #=> :validation
Errors.categorize("database_timeout")  #=> :persistence
Errors.categorize("connection_refused") #=> :network
```

### Contexts

Process-scoped request context for propagating metadata.

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
  comn.ex              Comn behaviour (look/recon/choices/act)
  errors.ex            Error wrapping and categorization
  events.ex            Pub/sub behaviour
  event_bus.ex         Registry-based pub/sub implementation
  event_log.ex         Agent-based append-only event log
  events/nats.ex       NATS adapter
  events/registry.ex   Registry adapter
  contexts.ex          Process-scoped context management
  secrets.ex           Secrets behaviour
  secrets/local.ex     ChaCha20-Poly1305 local encryption
  secrets/vault.ex     HashiCorp Vault Transit backend
  repo.ex              Base repo behaviour (describe/get/set/delete/observe)
  table.ex             Table behaviour (create/drop/keys/count)
  file.ex              File behaviour (open/load/stream/cast/read/write/close)
  graphs.ex            Graph behaviour (link/unlink/traverse)
  cmd.ex               Command behaviour (validate/apply/reset/enable/...)
  repo/table/ets.ex    ETS implementation
  repo/file/local.ex   Local filesystem implementation
  repo/file/nfs.ex     NFS mount-point wrapper
  repo/file/ipfs.ex    IPFS daemon API backend
  repo/graphs/graph.ex libgraph implementation
  repo/cmd/shell.ex    Shell command execution (placeholder)
  actor.ex             Actor-style repo (placeholder)
  infra.ex             Infrastructure management (placeholder)
```

## Running Tests

```bash
mix test                    # All tests (Vault tests auto-excluded)
VAULT_TOKEN=xxx mix test    # Include Vault integration tests
```

## License

AGPL-3.0
