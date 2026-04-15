# The Design of Comn — Literate Guide Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Write `guides/design.md` — a single long-form narrative explaining Comn's architecture and design rationale, readable on GitHub and as an ExDoc supplementary guide.

**Architecture:** Single markdown file with explicit anchor IDs on every H2/H3. Prose-driven with code blocks sourced from actual files (annotated with `<!-- from path -->` comments). Six sections following the top-down narrative arc from the spec.

**Tech Stack:** Markdown, Elixir code blocks (display only, not executed)

**Spec:** `docs/superpowers/specs/2026-04-15-literate-design-guide-design.md`

---

### Task 1: Create the file and write Section 1 — The Problem and the Principle

**Files:**
- Create: `guides/design.md`

- [ ] **Step 1: Create `guides/` directory**

Run: `mkdir -p guides`

- [ ] **Step 2: Write Section 1**

Write the opening of `guides/design.md`. This section establishes the core design insight: every module answers four questions.

Content must include:

1. **Opening paragraph** — The problem: in a system with many modules, discovering what exists and what it can do requires reading documentation or source. Comn makes this a runtime capability — every module is machine-queryable.

2. **The four callbacks** — `look` (what is this?), `recon` (what can it do?), `choices` (what are my options?), `act` (do it). Note the OODA-loop inspiration from the Anemos design.

3. **Three module types** — behaviour (defines the contract, returns `{:error, :behaviour_only}` from `act`), implementation (does the work), facade (orchestrates).

4. **Why it matters** — Orchestration layers, TUIs, CLI tools, and future autonomous agents can navigate the system programmatically. Discovery is not documentation — it's live metadata.

5. **Code block: the Comn behaviour definition** sourced from `lib/comn/comn.ex`:

```elixir
<!-- from lib/comn/comn.ex -->
@callback look() :: String.t()
@callback recon() :: map()
@callback choices() :: map()
@callback act(map()) :: {:ok, term()} | {:error, term()}
```

6. **Code block: the discovery loop in action** against `Comn.Repo`:

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

- [ ] **Step 3: Verify markdown renders**

Run: `head -80 guides/design.md`

Visually confirm: H1 title, H2 with anchor ID, prose paragraphs, two code blocks with `<!-- from -->` annotations, no broken markdown.

- [ ] **Step 4: Commit**

```bash
git add guides/design.md
git commit -m "Add guides/design.md Section 1: The Problem and the Principle"
```

---

### Task 2: Write Section 2 — Discovery

**Files:**
- Modify: `guides/design.md`

- [ ] **Step 1: Write Section 2**

Append Section 2 to `guides/design.md`. This section shows the consequence of universal introspection: the system indexes itself at boot.

Content must include:

1. **How it works** — `Comn.Discovery` scans `:code.all_loaded/0` for modules exporting all four Comn callbacks. Results indexed into `:persistent_term` (zero-cost reads, global to node, written once at boot).

2. **The lazy-loading problem** — BEAM only loads modules on first reference. Comn's own modules are listed in `@comn_modules` and `Code.ensure_loaded/1`'d before the scan. Consumer modules (`MyApp.Repo.Postgres`) are picked up automatically if loaded before discovery runs.

3. **Query API** — `all/0`, `by_type/1`, `implementations_of/1`, `lookup/1`. Show examples from the actual Discovery module.

4. **Design rationale: persistent_term over ETS** — Read-heavy workload (queries happen often, writes happen once at boot). No process ownership needed. No ETS table to name or protect. The tradeoff: updating persistent_term triggers a global GC pass on all processes, which is fine for write-once-at-boot but would be terrible for frequent updates.

5. **Design rationale: runtime scan over compile-time registry** — Consumer modules don't exist at Comn's compile time. A compile-time registry would only capture Comn's own modules. The runtime scan catches everything loaded on the node.

6. **Code block: the discovery scan** sourced from `lib/comn/discovery.ex`:

```elixir
<!-- from lib/comn/discovery.ex -->
def discover do
  Enum.each(@comn_modules, &Code.ensure_loaded/1)

  index =
    for {module, _} <- :code.all_loaded(),
        comn_module?(module),
        into: %{} do
      {module, build_meta(module)}
    end

  :persistent_term.put(@persistent_term_key, index)
  :ok
end
```

- [ ] **Step 2: Verify section appended correctly**

Run: `grep -n "^##" guides/design.md`

Expected: Two H2 headings (Section 1 and Section 2), each with anchor IDs.

- [ ] **Step 3: Commit**

```bash
git add guides/design.md
git commit -m "Add Section 2: Discovery — The System Knows Itself"
```

---

### Task 3: Write Section 3 — Cross-cutting Concerns

**Files:**
- Modify: `guides/design.md`

- [ ] **Step 1: Write the section intro and Contexts subsection**

Append the Section 3 opening and Contexts subsection. The opening paragraph establishes the key insight: Contexts, Errors, and Events are independent subsystems that compose through ambient process state.

**Contexts content:**

1. Why process dictionary is the right choice — same pattern as Logger metadata and OpenTelemetry baggage. The alternative (explicit parameter threading) would require every function to accept and forward a context argument.

2. How it works — `Comn.Contexts.new/1` stores a `ContextStruct` in the process dictionary. `fetch/1` reads from it. `with_context/2` provides scoped overrides with guaranteed restore via `try/after`.

3. Fields that propagate: `request_id`, `trace_id`, `correlation_id`, `user_id`, `actor`, `env`, `zone`, `parent_event_id`, `metadata`.

4. Code block sourced from `lib/comn/contexts.ex`:

```elixir
<!-- from lib/comn/contexts.ex -->
@key :comn_context

def new(fields) do
  ctx = ContextStruct.new(fields)
  set(ctx)
  ctx
end

def with_context(%ContextStruct{} = ctx, fun) do
  old = get()
  set(ctx)
  try do
    fun.()
  after
    case old do
      nil -> Process.delete(@key)
      prev -> set(prev)
    end
  end
end
```

- [ ] **Step 2: Write the Errors subsection**

Append the Errors subsection.

**Content:**

1. The decision and why — full `ErrorStruct` with registered namespace/code pairs, not bare atoms. Every error is traceable (enriched from ambient context), queryable (by prefix, by category, by HTTP status), and validated at compile time (duplicate codes rejected, format enforced by regex).

2. The six categories: `:validation`, `:persistence`, `:network`, `:auth`, `:internal`, `:unknown`. The `categorize/1` function uses keyword matching as a heuristic — not perfect, but useful for auto-categorizing unknown errors.

3. The `Comn.Error` protocol — `wrap/1` converts any term (string, map, tuple, existing struct) into an `ErrorStruct` via protocol dispatch.

4. The compile-time registry — `register_error` macro accumulates error definitions during compilation. `discover/0` at boot scans all loaded modules for `__errors__/0` and indexes them into persistent_term. Codes follow strict `namespace/error_name` format validated by regex at compile time.

5. Code block showing the registry macro sourced from `lib/comn/errors/registry.ex`:

```elixir
<!-- from lib/comn/errors/registry.ex -->
defmacro register_error(code, category, opts) do
  unless is_binary(code) and Regex.match?(~r/^[a-z][a-z0-9]*(\.[a-z][a-z0-9]*)*\/[a-z][a-z0-9_]*$/, code) do
    raise CompileError,
      description: "invalid error code #{inspect(code)} — must match namespace/error_name"
  end

  quote do
    @registered_errors %{
      code: unquote(code),
      category: unquote(category),
      message: unquote(Keyword.get(opts, :message)),
      status: unquote(Keyword.get(opts, :status)),
      suggestion: unquote(Keyword.get(opts, :suggestion)),
      module: __MODULE__
    }
  end
end
```

- [ ] **Step 3: Write the Events subsection**

Append the Events subsection.

**Content:**

1. The behaviour/adapter split — `Comn.Events` defines four callbacks (`start_link`, `broadcast`, `subscribe`, `unsubscribe`). Adapters implement them: `Comn.EventBus` (Registry-based, in-process), `Comn.Events.Registry` (also Registry-based), `Comn.Events.NATS` (external, opt-in).

2. EventStruct enrichment mirrors ErrorStruct — the `new/5` constructor pulls `request_id` and `correlation_id` from ambient `Comn.Contexts`. Same pattern, same fields, independent subsystem.

3. EventLog — Agent-based append-only log. Simple audit trail for dev and testing. Known limitation: unbounded list growth. Fine for development, not for production at scale.

4. Why NATS is opt-in — requires connection config (host, port) that Comn can't know. Lives in the consumer's supervision tree, not Comn's.

5. Code block showing EventStruct auto-enrichment sourced from `lib/comn/events/event_struct.ex`:

```elixir
<!-- from lib/comn/events/event_struct.ex -->
def new(type, topic, data, source \\ __MODULE__, opts \\ []) do
  ctx = Comn.Contexts.get()

  %__MODULE__{
    id: Comn.Secrets.Local.UUID.uuid4(),
    timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
    source: source,
    type: type,
    topic: topic,
    data: data,
    schema: Keyword.get(opts, :schema),
    version: Keyword.get(opts, :version, 1),
    tags: Keyword.get(opts, :tags, []),
    correlation_id: ctx && ctx.correlation_id,
    request_id: ctx && ctx.request_id,
    metadata: Keyword.get(opts, :metadata, %{})
  }
end
```

- [ ] **Step 4: Write the Composition Story subsection**

Append a short subsection showing an end-to-end example where all three subsystems compose. This is a synthetic example (not from source) demonstrating the flow:

```elixir
# Set context once at the request boundary
Comn.Contexts.new(request_id: "req-abc", trace_id: "trace-789", user_id: "user-42")

# Somewhere deep in the call stack, an error occurs — auto-enriched
{:ok, error} = Comn.Errors.wrap("database_timeout")
error.request_id      #=> "req-abc"
error.trace_id        #=> "trace-789"

# An event is broadcast — also auto-enriched from the same context
event = Comn.Events.EventStruct.new(:domain, "order.failed", %{reason: "timeout"})
event.request_id      #=> "req-abc"
event.correlation_id  #=> nil (not set in this context)

# Both carry the same request_id without anyone passing it explicitly
```

Prose after the example: no function in the call chain between the boundary and the error/event site needed to accept or forward a context argument. The process dictionary carries it. This is the same pattern Logger uses for metadata — it's idiomatic BEAM, not a hack.

- [ ] **Step 5: Verify all subsection headings**

Run: `grep -n "^##" guides/design.md`

Expected: H2 for Section 1, H2 for Section 2, H2 for Section 3, H3 for Contexts, H3 for Errors (or Error Philosophy), H3 for Events, H3 for Composition Story. All with anchor IDs.

- [ ] **Step 6: Commit**

```bash
git add guides/design.md
git commit -m "Add Section 3: Cross-cutting Concerns — Context, Errors, Events"
```

---

### Task 4: Write Section 4 — Secrets

**Files:**
- Modify: `guides/design.md`

- [ ] **Step 1: Write Section 4**

Append Section 4. This is a short section — the philosophy *is* the story.

**Content:**

1. **Philosophy** — Secrets are just encrypted data. No rotation schedules, no version stages, no key management opinions, no lifecycle. If you want rotation, call `lock/2` again. If you want versioning, store multiple blobs. Four verbs: `lock`, `unlock`, `wrap`, `unwrap`.

2. **Why ChaCha20-Poly1305** — AEAD cipher (authentication + encryption in one pass). No padding oracle attacks (stream cipher, not block cipher). Safe with random nonces (96-bit nonce space is large enough that collisions are negligible for reasonable volumes).

3. **Key derivation** — Ed25519 keys are asymmetric, but ChaCha20 needs a symmetric key. The private key is hashed with SHA-256 to derive 32 bytes. (Note in prose: production use should use HKDF for proper key derivation; the current approach is correct but not best-practice.)

4. **Wrap/unwrap design** — The container is encrypted as a whole, not just bundled. The AEAD authentication tag covers the entire serialized structure — blob order, blob count, metadata. This protects against reordering, deletion, injection, and replay attacks. An attacker who swaps blob order or removes a blob will fail authentication on unwrap.

5. **Vault backend** — Same `Comn.Secrets` behaviour, delegates lock/unlock to HashiCorp Vault's Transit engine. Key material never leaves Vault. Drop-in replacement — swap `Local` for `Vault` in the alias, add connection metadata to the key struct.

6. **Safety detail** — All `binary_to_term` calls use `[:safe]` to prevent atom exhaustion and arbitrary code execution from deserialized data.

7. **Code block** sourced from `lib/comn/secrets/local.ex`, showing the lock function's nonce generation and AEAD encryption:

```elixir
<!-- from lib/comn/secrets/local.ex -->
def lock(blob, %Key{} = key) when is_binary(blob) do
  with :ok <- validate_key(key) do
    symmetric_key = :crypto.hash(:sha256, key.private)
    nonce = :crypto.strong_rand_bytes(12)

    metadata = %{
      created_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      algorithm: key.algorithm
    }

    aad = :erlang.term_to_binary(metadata)

    {ciphertext, tag} = :crypto.crypto_one_time_aead(
      :chacha20_poly1305,
      symmetric_key,
      nonce,
      blob,
      aad,
      true
    )

    {:ok, %LockedBlob{
      ciphertext: ciphertext,
      nonce: nonce,
      tag: tag,
      key_id: key.id,
      metadata: metadata
    }}
  end
end
```

- [ ] **Step 2: Commit**

```bash
git add guides/design.md
git commit -m "Add Section 4: Secrets — Encryption Without Lifecycle"
```

---

### Task 5: Write Section 5 — The Repo Tree

**Files:**
- Modify: `guides/design.md`

- [ ] **Step 1: Write Section 5**

Append Section 5. This is the architectural centerpiece — the longest section.

**Content:**

1. **The premise** — All I/O falls into a small number of structural patterns. Rather than building bespoke interfaces for every backend, Comn defines a behaviour for each pattern and lets implementations fill in the details.

2. **Base contract: `Comn.Repo`** — Five verbs: `describe` (what is this resource?), `get` (retrieve), `set` (store), `delete` (remove), `observe` (stream or snapshot). Why five and not CRUD: `describe` gives introspection that CRUD lacks. `observe` gives streaming/enumeration. No `update` — update is `set` with an existing key. The simplicity is intentional: these five verbs are the common interface that every repo type shares.

3. **Code block: the Repo behaviour** sourced from `lib/comn/repo.ex`:

```elixir
<!-- from lib/comn/repo.ex -->
@type resource :: term()

@callback describe(resource()) :: {:ok, map()} | {:error, term()}
@callback get(resource(), keyword()) :: {:ok, term()} | {:error, term()}
@callback set(resource(), keyword()) :: :ok | {:ok, term()} | {:error, term()}
@callback delete(resource(), keyword()) :: :ok | {:ok, term()} | {:error, term()}
@callback observe(resource(), keyword()) :: Enumerable.t() | {:error, term()}
```

4. **The ten I/O shapes** — Each gets a paragraph explaining what structural pattern it represents and why it's distinct from the others:

   - **Table** — Keyed lookup with create/drop lifecycle. The most familiar shape: a named collection of key-value pairs. ETS implementation.
   - **File** — State machine lifecycle: `open` -> `load` -> `read`/`write`/`stream` -> `close`. The state machine prevents use-before-load and write-after-close errors at the type level. Local, NFS, IPFS implementations.
   - **Graphs** — Relationships: `link`/`unlink`/`traverse`. Not key-value — the data *is* the connections. libgraph implementation.
   - **Cmd** — Command pattern: `validate`/`apply`/`reset`. For operations that are executed, not stored. Shell placeholder.
   - **Batch** — Buffered write-behind: `push`/`flush`/`size`/`drain`/`status`. Accumulates writes and flushes on a size or time threshold. Mem (GenServer) implementation with configurable auto-flush.
   - **Column** — Schema-enforced columnar storage: `create`/`put`/`select`/`delete`/`schema`/`count`/`drop`. Rows conform to a declared schema. Projections select subsets of columns. ETS implementation.
   - **Bus** (planned) — Raw pub/sub transport. No struct opinions — publish bytes, subscribe to topics. Distinct from Events because Events is opinionated (EventStruct, enrichment, logging). Bus is the transport underneath.
   - **Queue** (planned) — Ordered, durable, ackable. The RabbitMQ/Oban pattern: enqueue, dequeue, acknowledge. Messages have delivery guarantees.
   - **Stream** (planned) — Append-only, replayable. The Kafka pattern: consumers read from an offset, the log is immutable and replayable.
   - **Merkel** (planned) — Content-addressed, immutable. The Git/IPFS pattern: data is addressed by its hash, storage is deduplicating, history is a DAG.

5. **Naming convention** — Behaviour at `Comn.Repo.X`, implementations at `Comn.Repo.X.Backend`. Example: `Comn.Repo.Table` (behaviour), `Comn.Repo.Table.ETS` (implementation). Consumer implementations follow the same pattern: `MyApp.Repo.Table.Postgres`.

6. **NFS design choice** — NFS wraps Local rather than reimplementing file I/O. It adds two concerns: path resolution relative to a mount point (with traversal protection) and ESTALE detection. Everything else delegates to Local. Why: NFS file operations *are* local file operations once you're past the mount.

7. **Path traversal on NFS vs Local** — NFS has a mount boundary to enforce, so `resolve_path/2` expands the path and verifies it stays within the mount prefix. Local doesn't have a mount boundary — it's deliberately "you get what you ask for." If Local is exposed to untrusted input, the consumer must add their own path policy.

- [ ] **Step 2: Commit**

```bash
git add guides/design.md
git commit -m "Add Section 5: The Repo Tree — Ten Shapes of I/O"
```

---

### Task 6: Write Section 6 — Supervision and Boot

**Files:**
- Modify: `guides/design.md`

- [ ] **Step 1: Write Section 6**

Append the final section. Short — it ties everything together.

**Content:**

1. **The boot sequence** — `Comn.Application.start/2` calls `Comn.Supervisor.start_link/0`. The supervisor brings up three children: two Registry instances (EventBus and Events.Registry, both `:duplicate` keys) and one EventLog Agent. Strategy is `one_for_one` — if EventLog crashes, it doesn't take down the bus.

2. **Post-supervision discovery** — After the tree is up, two discovery passes run sequentially:
   - `Comn.Errors.Registry.discover/0` — scans all loaded modules for `__errors__/0`, indexes error definitions into persistent_term
   - `Comn.Discovery.discover/0` — scans for modules exporting the four Comn callbacks, indexes metadata into persistent_term

3. **Why this order matters** — Supervision tree must be up first because EventBus is a Registry process that other modules may reference during discovery. Error discovery before module discovery because module metadata (from `recon/0`) may reference error codes.

4. **Code block: the full boot sequence** sourced from `lib/comn/application.ex`:

```elixir
<!-- from lib/comn/application.ex -->
def start(_type, _args) do
  result = Comn.Supervisor.start_link()

  Comn.Errors.Registry.discover()
  Comn.Discovery.discover()

  result
end
```

5. **Code block: the supervision tree** sourced from `lib/comn/supervisor.ex`:

```elixir
<!-- from lib/comn/supervisor.ex -->
def init(_opts) do
  children = [
    {Registry, keys: :duplicate, name: Comn.EventBus},
    {Registry, keys: :duplicate, name: Comn.Events.Registry},
    Comn.EventLog
  ]

  Supervisor.init(children, strategy: :one_for_one)
end
```

6. **What's NOT in the tree** — NATS and other external adapters require connection config Comn can't know. They belong in the consumer's supervision tree. Same for any future adapter (RabbitMQ for Queue, Kafka for Stream, etc.) — Comn provides the behaviour, the consumer provides the process.

7. **Known limitation: EventLog** — It's an Agent with an ever-growing list. Acceptable for development, testing, and audit trails on low-volume systems. Not suitable for production at scale. A future version may swap to a ring buffer or delegate to a durable backend.

8. **Closing paragraph** — Tie the arc together. The system starts, the tree comes up, discovery indexes what exists, and from that point forward any module — your code or Comn's — can be found, queried, and operated through the same four verbs. That's the design: uniform introspection from boot to shutdown.

- [ ] **Step 2: Verify complete document structure**

Run: `grep -n "^##" guides/design.md`

Expected output should show six H2 sections, plus H3 subsections under Section 3 (Contexts, Errors/Error Philosophy, Events, Composition), all with anchor IDs:

```
## The Problem and the Principle {#the-principle}
## Discovery — The System Knows Itself {#discovery}
## Cross-cutting Concerns — Context, Errors, Events {#cross-cutting}
### Contexts {#contexts}
### Errors {#error-philosophy}  (or ### Error Philosophy)
### Events {#events}
### The Composition Story {#composition}
## Secrets — Encryption Without Lifecycle {#secrets}
## The Repo Tree — Ten Shapes of I/O {#the-repo-tree}
## Supervision and Boot — How It Comes Alive {#boot}
```

- [ ] **Step 3: Verify all code block annotations**

Run: `grep "<!-- from" guides/design.md`

Expected: One annotation per code block sourced from actual files. Verify each path exists:
- `lib/comn/comn.ex`
- `lib/comn/discovery.ex`
- `lib/comn/contexts.ex`
- `lib/comn/errors/registry.ex`
- `lib/comn/events/event_struct.ex`
- `lib/comn/secrets/local.ex`
- `lib/comn/repo.ex`
- `lib/comn/application.ex`
- `lib/comn/supervisor.ex`

The composition example in Section 3 is synthetic (not from a source file) — it should NOT have a `<!-- from -->` annotation.

- [ ] **Step 4: Commit**

```bash
git add guides/design.md
git commit -m "Add Section 6: Supervision and Boot — How It Comes Alive"
```

---

### Task 7: Final review pass

**Files:**
- Modify: `guides/design.md`

- [ ] **Step 1: Read the complete document top-to-bottom**

Run: `wc -l guides/design.md` to check length, then read the full file.

Check for:
- Narrative coherence: does each section flow into the next?
- No placeholder text (TBD, TODO, "similar to above")
- No broken markdown (unclosed code blocks, malformed headers)
- Anchor IDs on every H2 and H3
- `<!-- from -->` annotations on every source-derived code block
- No `<!-- from -->` on the synthetic composition example
- Consistent voice throughout (design rationale, not tutorial)

- [ ] **Step 2: Fix any issues found**

Edit `guides/design.md` to address anything from Step 1.

- [ ] **Step 3: Final commit**

```bash
git add guides/design.md
git commit -m "Final review pass on guides/design.md"
```

Only commit if changes were made in Step 2. If the review pass found nothing, skip this commit.
