# Comn — Elixir Infrastructure Framework

## Current State (v0.3.0)

Flat Elixir app (flattened from umbrella Feb 14, 2026). Provides standardized abstractions for errors, events, secrets, contexts, repo, and infra.

**Build: 0 errors, 0 warnings. Tests: 84 pass, 0 failures.**

## Architecture

```
lib/comn/
  error.ex, errors.ex, error_struct.ex        Comn.Error protocol + categorization
  errors/impl/                                 Error protocol impls (Map, Struct, Tuple, String, Atom)
  event.ex, events.ex, event_struct.ex         Comn.Event protocol
  event_bus.ex, event_log.ex                   EventBus (Registry), EventLog (Agent)
  events/nats.ex, events/registry.ex           NATS adapter, Registry helpers
  events/impl/                                 Event protocol impls (Map, Struct, Tuple)
  secret.ex, secrets.ex                        Comn.Secret protocol + Secrets behaviour
  secrets/local.ex, secrets/vault.ex           ChaCha20 + Vault backends
  secrets/key.ex, locked_blob.ex, container.ex Secrets data types
  context.ex, contexts.ex, context_struct.ex   Context protocol + process-scoped mgmt
  policy_struct.ex, rule_struct.ex             Context policy types
  repo.ex, repo_struct.ex                      Repo behaviour
  repo/table/ets.ex, repo/table/ecto.ex        Table backends
  repo/file/, repo/cmd/, repo/graphs/          File/Cmd/Graph subsystems
  repo/merkel/                                 Git/GitHub integrations
  actor.ex, batch.ex, bus.ex, cmd.ex           Repo-adjacent modules
  column.ex, file.ex, graphs.ex, merkel.ex
  queue.ex, stream.ex, table.ex
  infra.ex, infra/                             Infrastructure (compute, storage, connectivity)
```

## Dependencies

```elixir
gnat ~> 1.11     # NATS messaging
jason ~> 1.4     # JSON
faker ~> 0.18    # Testing (test only)
```

## Usage as Dependency

```elixir
{:comn, github: "imsmith/comn", tag: "v0.3.0"}
```
