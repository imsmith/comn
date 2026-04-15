# Spec: The Design of Comn — Literate Programming Guide

## Overview

A single long-form markdown document (`guides/design.md`) that tells the story of how Comn is designed and why. Written as an ExDoc supplementary guide that also renders well on GitHub. Primary audience is the author and future collaborators understanding architectural rationale; secondary audience is potential adopters evaluating the library.

## Format

- Single file: `guides/design.md`
- ExDoc supplementary guide (add to `extras:` in `mix.exs` if ExDoc is configured)
- GitHub-renderable markdown with explicit anchor IDs on every section for deep-linking from moduledocs, commit messages, or Obsidian vault
- Prose-first with code blocks pulled from actual source — not a tutorial, not an API reference, but a design narrative
- Target length: 2500-3500 words (readable in one sitting, ~15 minutes)

## Narrative Arc

Top-down: start with the core design insight, then show how it plays out across every subsystem. A reader who understands section 1 can predict the shape of everything that follows.

## Sections

### 1. The Problem and the Principle {#the-principle}

**Purpose:** Establish the core design insight — every module answers four questions.

**Content:**
- The observation: in a system with many modules, the first question is always "what is this and what can it do?" Most libraries answer with documentation. Comn answers with code.
- The `look`/`recon`/`choices`/`act` loop as an OODA-inspired discovery protocol
- Three module types: behaviour (defines the contract), implementation (does the work), facade (orchestrates)
- Why it matters: orchestration layers, TUIs, and future agents can navigate the system without hardcoded knowledge
- Include the `Comn` behaviour definition (callbacks and their typespecs)
- Short interactive example: the four callbacks against `Comn.Repo`

### 2. Discovery — The System Knows Itself {#discovery}

**Purpose:** Show the consequence of universal introspection — the system can index itself.

**Content:**
- `Comn.Discovery` scans `:code.all_loaded/0` for modules exporting the four callbacks
- Indexed into `:persistent_term` — zero-cost reads, global to the node, written once at boot
- Queryable by type, by parent behaviour, by module
- The `@comn_modules` list: why it exists (BEAM lazy-loads, Comn's modules must be `ensure_loaded` before the scan)
- Consumer modules get picked up automatically if loaded before discovery runs
- Design rationale: persistent_term over ETS (read-heavy, write-once, no process ownership). Scan over compile-time registry (consumers can't register at Comn's compile time)

### 3. Cross-cutting Concerns — Context, Errors, Events {#cross-cutting}

**Purpose:** Explain the three subsystems that compose through ambient state.

**Subheadings with their own anchors:**

#### Contexts {#contexts}
- Process dictionary as ambient state (same pattern as Logger metadata, OpenTelemetry baggage)
- `with_context/2` scoped overrides with guaranteed restore
- Fields that propagate: request_id, trace_id, correlation_id, user_id, actor, env, zone

#### Errors {#error-philosophy}
- The decision: full `ErrorStruct` with registered namespace/code pairs, not bare atoms
- Why: every error is traceable (enriched from context), queryable (by prefix, category, HTTP status), validated at compile time (duplicates rejected, format enforced)
- Six categories and the `categorize/1` heuristic
- The `Comn.Error` protocol — `wrap/1` any term into structured error

#### Events {#events}
- Behaviour/adapter split: Events defines the contract, EventBus/Registry/NATS implement it
- EventStruct enrichment mirrors ErrorStruct enrichment — same ambient context, same fields
- EventLog as simple audit trail; known limitation (unbounded Agent list)
- NATS is opt-in, not in supervision tree

#### The Composition Story {#composition}
- End-to-end example: context set at boundary, error auto-enriches, event auto-enriches, both carry same request_id/trace_id without explicit passing

### 4. Secrets — Encryption Without Lifecycle {#secrets}

**Purpose:** Explain the deliberately minimal philosophy.

**Content:**
- Philosophy: secrets are just encrypted data. No rotation, no versioning, no lifecycle management.
- `lock`/`unlock`/`wrap`/`unwrap` — four verbs, nothing more
- ChaCha20-Poly1305 for Local: why (AEAD, no padding oracle, safe with random nonces)
- Ed25519 keys derive symmetric keys rather than encrypting directly (size limits)
- `wrap`/`unwrap` encrypts the whole container — AEAD tag covers structure against reordering/deletion/injection
- Vault backend: same behaviour, delegates to Transit, key never leaves Vault
- `:safe` flag on all `binary_to_term` calls

### 5. The Repo Tree — Ten Shapes of I/O {#the-repo-tree}

**Purpose:** The architectural centerpiece — all I/O falls into a small number of structural patterns.

**Content:**
- Base `Comn.Repo` contract: five verbs (`describe`/`get`/`set`/`delete`/`observe`)
- Why five and not CRUD: `describe` for introspection, `observe` for streaming, no `update` (update is set-with-existing-key)
- Each extension behaviour as a distinct I/O shape:
  - **Table** — keyed lookup, create/drop lifecycle
  - **File** — state machine: open → load → read/write/stream → close
  - **Graphs** — link/unlink/traverse
  - **Cmd** — command pattern: validate/apply/reset
  - **Batch** — buffered write-behind with auto-flush
  - **Column** — schema-enforced columnar with projections
  - **Bus** — raw pub/sub transport (planned)
  - **Queue** — ordered, durable, ackable (planned)
  - **Stream** — append-only, replayable (planned)
  - **Merkel** — content-addressed, immutable (planned)
- Naming convention: behaviour at `Comn.Repo.X`, implementations at `Comn.Repo.X.Backend`
- NFS wraps Local rather than standing alone (path resolution + ESTALE detection)
- Path traversal guard on NFS; why Local doesn't have one (no mount boundary — policy left to consumer)

### 6. Supervision and Boot — How It Comes Alive {#boot}

**Purpose:** Tie everything together by walking through application startup.

**Content:**
- `Comn.Application` → `Comn.Supervisor`
- Three children: EventBus Registry, Events.Registry, EventLog
- `one_for_one` strategy — EventLog crash doesn't take down the bus
- After tree is up: `Errors.Registry.discover/0` scans for `register_error` declarations
- Then `Discovery.discover/0` scans for `@behaviour Comn` modules
- Why discovery at boot, not compile time (consumer modules don't exist at Comn's compile time)
- Why NATS and optional adapters are NOT in this tree (require connection config Comn can't know)
- EventLog unbounded growth acknowledged as known limitation

## Code Examples

All code blocks should be actual source from the repo, not synthetic examples. Use the pattern:

```
<!-- from lib/comn/comn.ex -->
```elixir
@callback look() :: String.t()
...
```
```

This makes it clear where code lives and keeps the document honest — if the source changes and the doc doesn't, the comment tells you exactly what to update.

## What This Document Is Not

- Not an API reference (that's ExDoc's job)
- Not a tutorial (the README covers quickstart usage)
- Not a changelog (that's git history)
- Not a gap analysis or roadmap (that's in working notes)

It's a design narrative: the thinking behind the architecture, written for someone who wants to understand *why* before reading the code.

## Acceptance Criteria

- Single file at `guides/design.md`
- Renders correctly on GitHub (no ExDoc-specific syntax that breaks in plain markdown)
- Every H2/H3 has an explicit anchor ID
- Code blocks reference their source file
- Reads coherently top-to-bottom as a narrative
- Each section can be deep-linked independently
- No placeholder sections, no TODOs, no "TBD"
