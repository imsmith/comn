# ADR-0001: Every Repo shape is an event sink

**Status:** Accepted
**Date:** 2026-10-13
**Deciders:** Ian Smith

## Context

Comn's purpose is backend fungibility: a caller writes against a Comn
behaviour and the backend behind it can be swapped without touching the
caller. `Comn.Secrets` is the reference: `lock`, `unlock`, `wrap`, `unwrap`,
and everything else is translation to accommodate a backend.

`Comn.Repo` declares the common I/O verbs, `describe`, `get`, `set`,
`delete`, `observe`, and every repo shape implements them. In practice the
verbs are shared in name only. `set/2` takes a different keyword on every
shape:

| Shape | `set/2` expects |
|---|---|
| Table | `key:` and `value:` |
| Column | `value:` (a row) |
| Batch | `value:` |
| File | `value:` (iodata) |
| Graph | `vertex:` |
| Stream | `event:` |
| Queue | not a `Comn.Repo` implementation; has `push/2` |

A caller cannot hand the same fact to a table, a file, a graph, a queue, and
a stream with the same call. The fungibility promise holds within a shape
(swap `Stream.Mem` for `Stream.SQLite`) but not across shapes, and even
within Stream it fails: each backend has its own lifecycle verbs and callers
name the backend module directly.

The Tier 2 plan listed Bus, Queue, Stream, and Merkel as four shapes with
four "planned" paragraphs in the design guide, framed around messaging
products (RabbitMQ, Kafka, NATS). Building Stream to completion and then
starting on Bus exposed that the framing was wrong. The three messaging
shapes differ only in what the medium does with a message; the message is
the same.

The message is a `Comn.Events.EventStruct`: a timestamped fact with
structured headers (`id`, `timestamp`, `source`, `type`, `topic`,
`correlation_id`, `request_id`, `schema`, `version`, `tags`, `metadata`) and
a `data` payload. Stream already enforces this. Queue does not.

Two constraints shaped the decision:

- **Comn must not be self-referential.** `Comn.Events` (the pub/sub
  subsystem with its Registry and NATS adapters, enrichment, and log) and
  `Comn.Repo` are independent and stay that way. Depending on the
  `EventStruct` *type* is a dependency on a leaf data definition and is
  allowed. Depending on the Events *transport* from inside Repo is the
  ouroboros and is not.
- **A repo shape reduces to the pure expression of what it abstracts.**
  Extra verbs that exist to accommodate a backend belong in the backend.

## Decision

Everything that moves through or rests in a Repo shape is, by default, an
event. The shapes are destinations for facts; the verb is what the medium
does with the fact.

1. **One canonical `set` form across all shapes.** Every `Comn.Repo`
   implementation accepts `set(resource, event: %EventStruct{})` and
   translates it:

   | Shape | `set(h, event: e)` means |
   |---|---|
   | Table | store under `e.id` |
   | Column | one row; headers become columns, `data` is a column |
   | Graph | a vertex keyed by `e.id`, labelled with the event |
   | File | append one encoded line; a file of events is a log |
   | Batch | buffer it; flush as usual |
   | Queue | enqueue it |
   | Stream | append it |
   | Bus | publish it |

   The existing shape-specific keyword forms remain for backend-facing use.
   `observe/2` yields events back out of every shape. `get/2` by `id:`
   returns the event where the medium retains it.

2. **One cross-shape conformance spec.** A test-support macro,
   `Comn.EventSinkConformance`, runs against every backend of every shape:
   set an event, then observe or get, and the same event comes back. A new
   backend is a Comn backend when it passes this spec. This is the ideology
   as an executable artifact, in the same style as
   `Comn.StreamConformance`.

3. **Bus is a shape, kept small.** Publish is `set`, subscribe is
   `observe`, one Registry-backed implementation, the same conformance
   spec. It exists because the medium does something distinct with the
   fact (deliver to all, retain nothing), not because it is a product
   category. NATS core is a second backend when a consumer needs it.

4. **Queue becomes a `Comn.Repo` implementation.** `set(q, event: e)`
   enqueues; `push/2` stays for bare terms so the existing surface does
   not break. `observe/2` on a queue is a non-destructive view.

5. **Stream gets the Queue treatment.** A facade with `open(name,
   backend: :mem | :sqlite | :jetstream, ...)` returning a handle;
   callers never name a backend module; one `close` and one `drop`.
   `commit/3` and `position/2` are removed: they are consumer
   bookkeeping, not log verbs. Callers track offsets, as the original
   Phase 1 spec said.

6. **`type: :system` is a convention, not a gate.** Comn's own activity is
   emitted with `type: :system`. Shapes carry whatever event they are
   given and do not police it.

7. **The design guide's four "planned" paragraphs are replaced** by this
   decision. The axis that matters is what the medium does with a fact,
   and the table above is the whole taxonomy.

## Options Considered

### Option A: Bus as the raw transport beneath Events

Bus becomes the substrate the Events adapters are built on; Events adds
EventStruct and enrichment on top.

| Dimension | Assessment |
|---|---|
| Complexity | Medium: three adapters refactored |
| Fungibility gained | None for callers; Events already has pluggable adapters |
| Self-reference risk | High: Repo depends on Events transport, Events on Repo |

**Pros:** matches the original design-guide sentence.
**Cons:** the seam already exists as `Comn.Events`; this is the
ouroboros; it does nothing for the `set/2` inconsistency.

### Option B: Collapse Bus, Queue, and Stream into one channel

One module with `delivery: :broadcast | :compete` and a retention policy,
Queue's backends folded in as the compete corner.

| Dimension | Assessment |
|---|---|
| Complexity | High: rewrite of two shipped modules |
| Fungibility gained | Within messaging only |
| Self-reference risk | Low |

**Pros:** fewest modules; the two real properties become open options.
**Cons:** breaks Queue's calling surface; drops LIFO, find, remove;
still leaves Table, Column, Graph, File, and Batch with incompatible
`set/2`; over-unifies things whose backends genuinely differ.

### Option C: Canonical event form across every shape (chosen)

Keep the shapes. Make the event the universal payload and prove it with
one spec.

| Dimension | Assessment |
|---|---|
| Complexity | Medium: one new clause per shape, one macro, one facade |
| Fungibility gained | Across all shapes, for the first time |
| Self-reference risk | Low: Repo depends on a leaf struct only |

**Pros:** fixes the real gap; additive for every shape except Stream's
consumer-group verbs; the test encodes the principle so it cannot drift
again.
**Cons:** Stream's `commit`/`position` are removed three days after
shipping; Queue grows a Repo surface it did not have.

## Trade-off Analysis

Options A and B both start from the messaging shapes and try to fix
their relationship to each other. Neither touches the fact that a table
and a stream cannot take the same `set`. Option C starts from the payload
and lets the shapes be what they are. It is the only option that makes
"swap the backend without changing the caller" true across shape
boundaries, which is the point of Comn.

The cost is a small amount of removed API in Stream. It is unreleased on
Hex, three days old, and has no callers.

## Consequences

- Easier: writing a consumer that does not know or care whether its
  facts land in a log file, a table, or a queue. Adding a backend: pass
  one spec.
- Easier: reasoning about the Repo family. One payload, one verb set, a
  table of what each medium does.
- Harder: shape-specific forms still exist and must stay documented as
  backend-facing. Column's translation of headers to columns needs a
  stable schema.
- Harder: Stream callers using `commit`/`position` must track offsets
  themselves. None exist today.
- Revisit: whether `Comn.EventLog` (an Agent holding a list) should be a
  retained Stream. Not decided here; Events keeps its own storage for now.
- Revisit: Merkel is on a different axis (addressing by content, not
  position). It is unaffected by this decision and remains the next real
  gap.

## Action Items

1. [x] `Comn.EventSinkConformance` macro in `test/support/`; wire it for
       Table.ETS, Column.ETS, Graph, File.Local, Batch.Mem, Queue (Mem,
       SQLite), Stream (Mem, SQLite, JetStream gated). Watch it fail.
2. [x] `set(h, event:)`, `get(h, id:)`, and event-yielding `observe/2`
       on each existing shape, one commit per shape.
3. [x] Queue implements `Comn.Repo`.
4. [x] Stream facade and handle; backends private; remove
       `commit`/`position`; update conformance, README, guide.
5. [ ] `Comn.Repo.Bus` behaviour + Registry backend, through the same
       spec.
6. [ ] Design guide: replace the planned paragraphs with the decision
       table; README status rows; delete nothing else.
