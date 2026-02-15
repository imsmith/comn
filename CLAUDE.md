# Comn — Elixir Infrastructure Framework

## Current State (v0.4.0)

Flat Elixir app (flattened from umbrella Feb 14, 2026). Provides standardized abstractions for errors, events, secrets, contexts, repo, and infra.

**Build: 0 errors, 0 warnings. Tests: 122 pass, 0 failures.**

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
  file.ex                                      Comn.Repo.File behaviour (lifecycle: open→load→read/write/stream→close)
  repo/file/file_struct.ex                     FileStruct (path, handle, state, backend, metadata, buffer)
  repo/file/local.ex                           Local filesystem backend
  repo/file/nfs.ex                             NFS mount-point backend (wraps Local)
  repo/file/ipfs.ex                            IPFS daemon API backend
  graphs.ex                                    Comn.Repo.Graphs behaviour (link, unlink, traverse)
  repo/graphs/graph_struct.ex                  GraphStruct (id, name, graph, directed?, metadata)
  repo/graphs/graph.ex                         libgraph backend (pure functional, no Agent)
  repo/cmd/, repo/merkel/                      Cmd/Git subsystems
  actor.ex, batch.ex, bus.ex, cmd.ex           Repo-adjacent modules
  column.ex, merkel.ex, queue.ex, stream.ex, table.ex
  infra.ex, infra/                             Infrastructure (compute, storage, connectivity)
```

## Dependencies

```elixir
gnat ~> 1.11       # NATS messaging
jason ~> 1.4       # JSON
req ~> 0.5         # HTTP (IPFS backend)
libgraph ~> 0.16   # In-memory graphs
faker ~> 0.18      # Testing (test only)
```

## Graph API

The graph behaviour is three callbacks — everything else goes through Repo:

```elixir
# Create a graph (caller holds the struct)
{:ok, gs} = Comn.Repo.Graphs.Graph.create(name: "my-graph")

# link/unlink — the graph-specific operations
{:ok, gs} = Graph.link(gs, :a, :b, label: "knows", weight: 1)
{:ok, gs} = Graph.unlink(gs, :a, :b)

# traverse — graph-specific queries
{:ok, path} = Graph.traverse(gs, type: :shortest_path, from: :a, to: :d)
{:ok, nodes} = Graph.traverse(gs, type: :reachable, from: :a)
{:ok, neighbors} = Graph.traverse(gs, type: :neighbors, vertex: :a)

# Repo callbacks handle nodes
{:ok, gs} = Graph.set(gs, vertex: :x)
{:ok, :x} = Graph.get(gs, vertex: :x)
{:ok, gs} = Graph.delete(gs, vertex: :x)
```

## Usage as Dependency

```elixir
{:comn, github: "imsmith/comn", tag: "v0.4.0"}
```
