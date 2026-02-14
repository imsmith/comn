# Comn — Elixir Infrastructure Framework

## Sprint Context

Active sprint through Feb 28, 2026. Full plan: `/home/imsmith/Documents/remote.vault.001/src/099 Katachora/SPRINT-2026-02.md`

Comn is Phase 1 (Feb 13-18). **Days 1-5 complete. Ready for tag.**

## What Comn Is

An Elixir umbrella project providing standardized abstractions for common infrastructure: errors, events, secrets, contexts, repo, and infra. Other projects (LLMAgent, Bookweb, media_stream, etc.) depend on it.

## Current State (as of Feb 15, 2026)

- **Secrets**: Complete. ChaCha20-Poly1305 local + HashiCorp Vault backends. 20 tests (10 Vault excluded without VAULT_TOKEN).
- **Events**: Working. EventBus (Registry-based pub/sub), EventLog (Agent-based append-only log), NATS adapter (Gnat). 14 tests.
- **Errors**: Working. Error protocol, ErrorStruct, categorization (validation/persistence/network/auth/internal/unknown), wrap/new. 18 tests.
- **Contexts**: Working. ContextStruct with request_id/trace_id/correlation_id/user_id/actor/env/zone/metadata. Process-scoped via process dictionary. with_context/2 for temporary scope. 16 tests.
- **Repo**: ETS key-value store (Table.ETS) complete. Behaviours defined for Table, File, Cmd, Graphs. Stub modules stripped of broken behaviour declarations. 15 tests.
- **Infra**: Placeholder. No implementation needed this sprint.

**Build: 0 errors, 0 warnings. Tests: 84 pass, 0 failures.**

## Architecture

```
apps/
  errors/     Comn.Error protocol + Comn.Errors (categorization)
  events/     Comn.Events behaviour + EventBus, EventLog, NATS adapter
  secrets/    Comn.Secrets behaviour + Local (ChaCha20) + Vault (Transit)
  contexts/   Comn.Context protocol + Comn.Contexts (process dictionary)
  repo/       Comn.Repo behaviour + Table.ETS implementation
  infra/      Placeholder
```

## Sprint Goal for Comn

**Exit criteria — ALL MET:**
```
mix compile  -> 0 errors, 0 warnings  ✓
mix test     -> 84 pass, 0 failures   ✓
README       -> documents what works  ✓
git tag      -> v0.2.0                pending
```

## Dependencies

```elixir
# mix.exs
gnat ~> 1.11     # NATS messaging
faker ~> 0.18    # Testing
cabbage ~> 0.4.1 # BDD testing
jason ~> 1.4     # JSON (in secrets app)
```

## What Was Done This Sprint

### Day 1 (Feb 13)
- Fixed ContextStruct syntax error, implemented full struct with metadata
- Replaced Contexts (had Events callbacks copy-pasted) with process-scoped context management
- Replaced Errors hello-world stub with real categorization
- Fixed String.Chars impl for ErrorStruct (was returning struct, not string)
- Added Comn.Error protocol impls for BitString and Atom
- Fixed Events alias bug (Comn.Event.EventStruct → Comn.Events.EventStruct)
- Rewrote all test files (were referencing bare module names)

### Day 2 (Feb 14)
- Rewrote NATS adapter with correct Gnat API
- Removed RabbitMQ adapter and amqp dependency
- Implemented Comn.Repo.Table behaviour (create, drop, keys, count)
- Implemented Comn.Repo.Table.ETS backend (full CRUD + table lifecycle)
- Fixed ETS test setup (catch_error → direct call)

### Day 3 (Feb 15)
- Stripped broken behaviour declarations from stub modules (Actor, Shell, CIFS, Graph)
- Fixed Infra orphaned @doc
- Fixed vault_test.exs unused variable warnings
- Reviewed Secrets — both backends complete (lock/unlock/wrap/unwrap)
- Rewrote README with real documentation and usage examples
- Zero compilation warnings achieved
