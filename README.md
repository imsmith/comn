# Comn

Elixir umbrella providing standardized abstractions for common infrastructure: error handling, event systems, secrets management, repository access, and request context propagation. Designed as a shared foundation for Elixir applications.

## Status

**v0.2.0** — Compiles clean, all tests pass.

| App | Status | Description |
|---|---|---|
| **secrets** | Complete | ChaCha20-Poly1305 local encryption + HashiCorp Vault Transit backend |
| **events** | Working | Registry-based pub/sub (EventBus), Agent-based log (EventLog), NATS adapter |
| **errors** | Working | Error protocol, categorization, wrapping for strings/atoms/maps |
| **contexts** | Working | Process-scoped request context with propagation |
| **repo** | Partial | ETS-backed key-value store. Table, File, Cmd, Graph behaviours defined |
| **infra** | Placeholder | Not yet implemented |

## Installation

Add Comn as a path dependency:

```elixir
defp deps do
  [
    {:comn, path: "../comn"}
  ]
end
```

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

# Lock (encrypt)
{:ok, locked} = Local.lock("sensitive data", key)

# Unlock (decrypt)
{:ok, "sensitive data"} = Local.unlock(locked, key)

# Wrap multiple locked blobs into a single encrypted container
{:ok, locked1} = Local.lock("secret 1", key)
{:ok, locked2} = Local.lock("secret 2", key)
{:ok, container} = Local.wrap([locked1, locked2], key)

# Unwrap to get individual blobs back
{:ok, [^locked1, ^locked2]} = Local.unwrap(container, key)
```

The Vault backend (`Comn.Secrets.Vault`) uses the same interface but delegates to HashiCorp Vault's Transit engine. Configure via key metadata:

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
alias Comn.Events.{EventBus, EventLog, EventStruct}

# Start the bus (add to your supervision tree)
Registry.start_link(keys: :duplicate, name: Comn.EventBus)

# Subscribe to a topic
EventBus.subscribe("user.created")

# Broadcast an event
event = EventStruct.new("user.created", :domain, %{user_id: 42})
EventBus.broadcast(event)

# Receive in subscribing process
receive do
  {:event, ^event} -> IO.puts("Got it!")
end

# Event log for audit/replay
{:ok, log} = EventLog.start_link()
EventLog.record(log, event)
EventLog.all(log)        # => [event]
EventLog.for_topic(log, "user.created")  # => [event]
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
Errors.categorize("invalid_format")    # => :validation
Errors.categorize("database_timeout")  # => :persistence
Errors.categorize("connection_refused") # => :network
```

### Contexts

Process-scoped request context for propagating metadata (request IDs, trace IDs, user info).

```elixir
alias Comn.Contexts

# Create and set a context for the current process
ctx = Contexts.new(request_id: "req-123", user_id: "user-42")

# Read values
Contexts.fetch(:request_id)  # => "req-123"

# Temporary context scope
Contexts.with_context(%{request_id: "req-456"}, fn ->
  Contexts.fetch(:request_id)  # => "req-456"
end)
Contexts.fetch(:request_id)  # => "req-123" (restored)
```

### Repo (ETS)

Key-value store backed by ETS.

```elixir
alias Comn.Repo.Table.ETS

{:ok, _} = ETS.create(:my_cache)

ETS.set(:my_cache, key: "user:1", value: %{name: "Ian"})
{:ok, %{name: "Ian"}} = ETS.get(:my_cache, key: "user:1")

{:ok, keys} = ETS.keys(:my_cache)   # => ["user:1"]
{:ok, 1} = ETS.count(:my_cache)

ETS.delete(:my_cache, key: "user:1")
ETS.drop(:my_cache)
```

## Architecture

Comn is an umbrella project. Each app defines behaviours (interfaces) and provides at least one implementation:

```
apps/
  errors/     Comn.Error protocol + Comn.Errors (categorization)
  events/     Comn.Events behaviour + EventBus, EventLog, NATS adapter
  secrets/    Comn.Secrets behaviour + Local (ChaCha20) + Vault (Transit)
  contexts/   Comn.Context protocol + Comn.Contexts (process dictionary)
  repo/       Comn.Repo behaviour + Table.ETS implementation
  infra/      Placeholder (not yet implemented)
```

## Not Yet Implemented

These behaviours are defined but have no implementations yet:

- `Comn.Repo.File` — File-system repositories (CIFS, IPFS, local)
- `Comn.Repo.Cmd` — Command/configuration repositories (shell)
- `Comn.Repo.Graphs` — Graph database repositories (libgraph)
- `Comn.Repo.Table` (Ecto) — Database-backed table repository
- `Comn.Infra` — Infrastructure management

## Running Tests

```bash
mix test                    # All tests (Vault tests auto-excluded)
VAULT_TOKEN=xxx mix test    # Include Vault integration tests
```

## License

Private.
