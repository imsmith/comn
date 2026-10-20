# Issues

Tracked here until they migrate to a real issue tracker. Newest first.

## Safe-decode constraint is enforced only on read, and not by the SQLite queue

**Filed:** 2026-10-13
**Reported from:** integrating comn v0.6.3 into paperclip

### Symptom

`guides/design.md:420` states the rule: every `binary_to_term` uses `[:safe]`
so deserialized data cannot exhaust the atom table. The consequence for
callers is that stored data must be atom-free beyond atoms the reading VM is
guaranteed to have. Two things undercut the rule.

**Writes accept what reads will reject.** `Comn.Repo.Stream.append/2`,
`Comn.Repo.Table.set/4`, and `Comn.Repo.Merkel.put/2` take any term. A caller
who appends an event with data like `%{user_id: 42}` or a module atom as
`source` gets `{:ok, offset}`. The failure arrives later, on a different VM
that has not yet created those atoms:

```text
** (ArgumentError) errors were found at the given arguments:
  * 1st argument: invalid or unsafe external representation of a term
    :erlang.binary_to_term(<<131, ...>>, [:safe])
    (comn 0.6.2) lib/comn/repo/stream/sqlite.ex:186: Comn.Repo.Stream.SQLite.select_events/3
```

Reproduced from paperclip: an `EventStruct` with `source: Paperclip.Customer`
and schema-field atom keys in `data` was appended in one `mix run`, then
`Stream.read/3` crashed the stream GenServer in the next. In a release
(embedded mode) every module loads at boot so the same data reads fine, which
makes the failure environment-dependent and hard to attribute.

The README encourages the pattern it rejects: the Events, Table, Stream, and
Merkel examples all use atom-keyed maps as `data`.

**The SQLite queue backend skips the flag.** `lib/comn/repo/queue/sqlite.ex`
decodes at lines 128, 167, and 196 with plain `binary_to_term/1`. It is the one
durable backend that does not follow the design guide, so a queue accepts and
replays atom-bearing payloads that a stream or table would refuse.

### Why it happens

`[:safe]` is a read-side guard chosen for its security property. Nothing on
the write side mirrors it, and the queue backend was written without it.

### What should change

Pick one and apply it everywhere:

1. **Enforce at write.** Reject (or `{:error, repo/unsafe_term}`) any term
   whose external representation contains an atom outside a known-safe set,
   checked once at `append`/`set`/`put`. Costs a walk of the term per write;
   moves the failure to the caller who made the mistake.
2. **Document and keep.** Add a "data must be atom-free" line to the
   `Comn.Repo.Stream`, `Table`, `Merkel`, and `Events.EventStruct` docs, fix
   the README examples to use string keys, and add `[:safe]` to the three
   queue decode sites so the rule is uniform.

Either way the queue backend needs the flag; the current state is the worst of
both, because it is neither safe nor consistent.

---

## Five source files under `lib/comn/repo/` are zero bytes

**Filed:** 2026-08-04
**Reported from:** as-built architecture review

### Symptom

```text
$ ls -la lib/comn/repo/bus.ex lib/comn/repo/merkel.ex \
         lib/comn/repo/merkel/git.ex lib/comn/repo/merkel/github.ex \
         lib/comn/repo/table/ecto.ex
-rw-r--r-- 1 imsmith imsmith 0 Feb 14 13:46 lib/comn/repo/bus.ex
-rw-r--r-- 1 imsmith imsmith 0 Feb 14 13:46 lib/comn/repo/merkel.ex
-rw-r--r-- 1 imsmith imsmith 0 Feb 14 13:46 lib/comn/repo/merkel/git.ex
-rw-r--r-- 1 imsmith imsmith 0 Feb 14 13:46 lib/comn/repo/merkel/github.ex
-rw-r--r-- 1 imsmith imsmith 0 Feb 14 13:46 lib/comn/repo/table/ecto.ex
```

No `defmodule` in any of them. `Comn.Repo.Bus` and `Comn.Repo.Merkel` do not
exist as atoms after compilation, yet `arch/diagrams/comn.c4:110` and
`comn.c4:140` both declare them as components of the Repo container, and the
Repo component view at `comn.c4:252` includes `bus` and `merkel` alongside the
backends that do exist. A reader of the diagram cannot tell the difference.

`lib/comn/repo/table/ecto.ex` is claimed by nothing at all — not the diagram,
not the README status table.

### Why it happens

The files were created as placeholders on 2026-02-14 (all five share that
mtime) and never filled in. Empty `.ex` files compile silently, so nothing in
the build flags them.

### What should change

Decide per file: either write the module or delete the file. An empty file that
is named in an architecture diagram is worse than an absent one, because it
survives `ls` and `find` and reads as implemented. The README already lists
Repo.Bus and Repo.Merkel as `Planned` — the diagram should agree, or the files
should go.

---

## `Repo.Actor` and `Repo.Cmd.Shell` are stubs that answer every call with `:not_implemented`

**Filed:** 2026-08-04
**Reported from:** as-built architecture review

### Symptom

`lib/comn/repo/actor.ex` is 32 lines and self-reports its own status:

```elixir
  @impl Comn
  def recon do
    %{status: :not_implemented, extends: Comn.Repo, type: :implementation}
  end

  @impl Comn
  def choices, do: %{}

  @impl Comn
  def act(_input), do: {:error, :not_implemented}
```

`lib/comn/repo/cmd/shell.ex:22-30` is the same shape, 31 lines. It is the only
backend for `Comn.Repo.Cmd`, whose behaviour at `lib/comn/repo/cmd.ex` is real
and declares thirteen lifecycle callbacks — `validate`, `apply`, `reset`,
`enable`, `disable`, `sync`, `status`, `test`, `invoke`, `info`, `watch`, `run`,
`probe`. `Cmd.Shell` implements none of them; it implements only the four
`Comn` introspection callbacks, and `act/1` returns `{:error, :not_implemented}`.

The diagram at `comn.c4:98` and `comn.c4:116` lists both as Repo components with
no marking. `comn.c4:164-186` gives both the same `process -[ipc]-> …  "Uses"`
and `… -[message]-> program "Sends messages to"` relationships as the working
backends.

### Why it happens

Both were written to satisfy `@behaviour Comn` so that discovery and
introspection see a uniform surface, before any of the actual work existed. The
introspection contract is honest — `recon/0` says `:not_implemented` — but
nothing above it reads that field.

### What should change

Either implement `Cmd.Shell` against the `Comn.Repo.Cmd` callback set, or move
`Comn.Repo.Cmd` to `Planned` in the README (it currently reads
`Repo.Cmd | Complete | Command behaviour (Shell placeholder)`, which claims more
than the code delivers). The same question applies to `Repo.Actor`, which the
README does not list at all.

Separately worth deciding: whether `Comn.Discovery` should filter or flag
modules whose `recon/0` reports `status: :not_implemented`, so the stub state is
visible to consumers rather than only to whoever opens the file.

---

## `comn.c4` gets all four Errors component names wrong

**Filed:** 2026-08-04
**Reported from:** as-built architecture review

### Symptom

`arch/diagrams/comn.c4:51-73` declares four components under the Errors
container:

```text
Comn.Error.ErrorStruct
Comn.Error.ErrorBehavior
Comn.Error.Impl
Comn.Error.Protocol
```

None of those four module names exist. What actually compiles:

```text
$ grep -rhoE "^(defmodule|defprotocol|defimpl) [A-Za-z0-9_.]+" \
      lib/comn/errors.ex lib/comn/errors/ lib/comn/error.ex
defmodule Comn.Errors.ErrorStruct
defprotocol Comn.Error
defimpl Comn.Error          (x4, in lib/comn/errors/impl/)
defmodule Comn.Errors
defmodule Comn.Errors.Registry
```

The family is `Comn.Errors.*` (plural). The single thing named `Comn.Error` is
the protocol — which the diagram calls `Comn.Error.Protocol`, a name that does
not exist. `Comn.Error.ErrorBehavior` and `Comn.Error.Impl` correspond to
nothing nameable: the behaviour consumers implement is `Comn` itself
(`lib/comn/comn.ex`, callbacks `look/0` `recon/0` `choices/0` `act/1`), and the
"impl" is four `defimpl Comn.Error` files, not a module.

`Comn.Errors.Registry` — the compile-time error-code registry that docindex and
cozybase both build on — appears nowhere in the diagram.

### What should change

Rename the four components to the modules that exist, add
`Comn.Errors.Registry`, and fix the relationships at `comn.c4:75-78`, which
describe an implements/uses chain that the protocol-plus-defimpl structure does
not have.

---

## `comn.c4` omits the kernel, every backend, the installers, and every external system

**Filed:** 2026-08-04
**Reported from:** as-built architecture review

### Symptom

`arch/diagrams/comn.c4` models six containers (Contexts, Errors, Events, Infra,
Repo, Secrets) and fifteen components, eleven of them under Repo. Absent from
the file entirely:

- The `Comn` behaviour itself — `lib/comn/comn.ex`, callbacks `look/0`
  `recon/0` `choices/0` `act/1`. This is the introspection contract the whole
  README is written around, and every module in the tree declares
  `@behaviour Comn`.
- The OTP boot path: `Comn.Application`, `Comn.Supervisor`, `Comn.Discovery`,
  `Comn.Zone`, `Comn.Presence` (`lib/comn/application.ex`, `supervisor.ex`,
  `discovery.ex`, `zone.ex`, `presence.ex`).
- `Comn.Errors.Registry`.
- Every concrete Repo backend: `Table.Ets`, `File.Local`, `File.Nfs`,
  `File.Ipfs`, `Queue.Mem`, `Queue.Sqlite`, `Stream.Mem`, `Batch.Mem`,
  `Column.Ets`, `Cmd.Shell`, `Graphs.Graph`. The diagram stops at the
  behaviour level.
- The installers: `lib/mix/tasks/comn.install.ex`, `lib/mix/tasks/comn.bootstrap.ex`.
- Components for Contexts (5 modules), Events (11) and Secrets (9). Those three
  containers are declared with no contents at all — see `comn.c4:40`, `:81`,
  `:190` — and their component views (`:225`, `:237`, `:255`) include only the
  generic `process` and `program` actors.
- Every external system. Real egress is NATS via `gnat` (`mix.exs:25`), Vault
  Transit via `Req` (`mix.exs:27`), the IPFS daemon via `Req`, the POSIX
  filesystem, and SQLite via `exqlite` (`mix.exs:29`). The only elements outside
  the system boundary in `comn.c4` are two abstract actors, `process` and
  `program` (`comn.c4:17-25`).

### Why it happens

The file predates most of the code. It describes the shape the project was
planned to have, not the shape it has.

### What should change

The `*-as-built.c4` files added alongside it in `arch/diagrams/` cover this
ground. The open question is what `comn.c4` is now for. Two constraints on any
answer:

1. `comn.c4` owns the `specification { }` block for the directory. LikeC4
   merges every `.c4` file in a directory into one model and permits each
   element kind to be declared only once, so the as-built files deliberately do
   not repeat it and reuse its kinds (`actor`, `system`, `container`,
   `component`; `ipc`, `message`, `rpc`). Deleting `comn.c4` breaks all of them.
2. The unnamed top-level `view { include * }` at `comn.c4:213` now also pulls in
   every as-built element, since they share the merged model.

So the fix is not "delete it". Likely: strip `comn.c4` down to the
specification block, and scope or remove the `include *` view.

---

## `comn.c4` names `Comn.Repo.Graph`; the module is `Comn.Repo.Graphs`

**Filed:** 2026-08-04
**Reported from:** as-built architecture review

### Symptom

`arch/diagrams/comn.c4:134-138` declares:

```text
        component graph {
            title 'Comn.Repo.Graph'
            description 'A module for managing graphs stores.'
            technology 'Elixir Module'
        }
```

The module is plural, and it has two modules beneath it that the diagram does
not show:

```text
lib/comn/repo/graphs.ex              defmodule Comn.Repo.Graphs
lib/comn/repo/graphs/graph.ex        defmodule Comn.Repo.Graphs.Graph
lib/comn/repo/graphs/graph_struct.ex defmodule Comn.Repo.Graphs.GraphStruct
```

`Graphs.Graph` is the libgraph-backed implementation; `Graphs.GraphStruct` is
the struct. The README already uses the correct name (`Repo.Graphs | Complete`).

### What should change

Rename the component title to `Comn.Repo.Graphs` and add the two modules under
it, or drop the component if the as-built diagrams are taking over.

---

## `comn.c4` describes Infra as a collection of modules; it is one placeholder over six empty files

**Filed:** 2026-08-04
**Reported from:** as-built architecture review

### Symptom

`arch/diagrams/comn.c4:87-91`:

```text
        infra = container {
            title 'Infra'
            description 'A collection of modules for infrastructure-related tasks.'
            technology 'Elixir Application'
        }
```

`lib/comn/infra.ex` is 34 lines whose own moduledoc contradicts that:

```elixir
  @moduledoc """
  Placeholder behaviour for infrastructure management.

  Not yet implemented. Will cover compute, storage, connectivity, and
  platform-specific backends (Proxmox, Unifi, etc.).
```

Its `act/1` returns `{:error, :not_implemented}` and `recon/0` reports
`%{status: :not_implemented, type: :behaviour}`. Everything under it is zero
bytes:

```text
$ ls -la lib/comn/infra/
-rw-r--r-- 1 imsmith imsmith 0 Feb 14 13:46 compute.ex
-rw-r--r-- 1 imsmith imsmith 0 Feb 14 13:46 connectivity.ex
-rw-r--r-- 1 imsmith imsmith 0 Feb 14 13:46 linux.ex
-rw-r--r-- 1 imsmith imsmith 0 Feb 14 13:46 proxmox.ex
-rw-r--r-- 1 imsmith imsmith 0 Feb 14 13:46 storage.ex
-rw-r--r-- 1 imsmith imsmith 0 Feb 14 13:46 unifi.ex
```

The diagram also gives Infra live relationships it cannot have — `comn.c4:199`
and `:200`, "Reports errors to" and "Sends events to".

### What should change

Match the README, which already says `Infra | Placeholder | Not yet
implemented`. Either mark the container as planned in the diagram or drop it
until there is code. The six empty files should be written or deleted; see the
zero-byte-files issue above.

---

## README lists `Repo.Stream` as Planned; `Stream.Mem` is implemented

**Filed:** 2026-08-04
**Reported from:** as-built architecture review

### Symptom

`README.md:30`:

```text
| Repo.Stream | Planned | Append-only, replayable (Kafka pattern) |
```

and `README.md:390`:

```text
  repo/stream.ex             Stream behaviour (planned)
```

`lib/comn/repo/stream/mem.ex` is 290 lines of working ETS `:ordered_set` code —
named tables keyed by monotonic integer offsets allocated with
`:ets.update_counter/3`, values are `Comn.Events.EventStruct`, with
`create/1`, `drop/1`, `append/2`, `head/1` and doctests that exercise the round
trip.

### Why it happens

This one drifts in the opposite direction from the diagram issues above: the
code got ahead of the document rather than behind it. Nothing updates the
status table when a backend lands.

### What should change

Set `Repo.Stream` to `Complete` with the Mem backend noted, matching how
`Repo.Queue` is already described (`Complete | … backends: Mem (ETS), SQLite`).
Fix the `(planned)` annotation at `README.md:390` too.
