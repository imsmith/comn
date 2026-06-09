# comn + busybody Igniter Installers — Design

**Date:** 2026-06-09
**Status:** Approved (brainstorm complete, ready for implementation plan)
**Repos touched:** `comn` (new tasks), `busybody` (installer rewrite)
**Out of scope (follow-on):** scaffolding the `updater` Phoenix app

## Problem

Wiring `comn` and `busybody` into a new Phoenix app is a repeated, mechanical
chore. busybody already ships a hand-rolled `mix busybody.install` (regex/line
patching of `mix.exs` and `application.ex`). comn ships no installer at all — its
documented integration is done by hand each time. We do this often enough to
automate it once, properly, with a single command that pulls both in as
dependencies and applies the integration changes each repo documents.

## Goals

- One reusable command, `mix comn.bootstrap`, that wires both libraries into a
  host Phoenix app in a single run.
- Each library also installable on its own: `mix comn.install`,
  `mix busybody.install`.
- Built on **Igniter** (AST-based codemods) so the two installers compose under
  one Igniter run and produce a single reviewable diff.
- Idempotent and flag-gated — every generated/patched piece is opt-out, and
  re-running is safe.

## Non-Goals

- Scaffolding the `updater` Phoenix app (separate follow-on; updater will be the
  first real consumer and an end-to-end fixture later).
- Publishing comn/busybody to Hex. They remain local sibling **path deps**.
- Changing either library's runtime behavior. Only installer tooling changes
  (plus busybody gaining `igniter` as a dep for its installer).

## Architecture

Three Mix tasks, all living in **comn** as the home of the tooling, all built on
Igniter. busybody's installer is rewritten in place.

```text
comn/
  lib/mix/tasks/comn.install.ex      # Igniter.Mix.Task — wire comn into host app
  lib/mix/tasks/comn.bootstrap.ex    # combined command — both deps + both installers

busybody/
  lib/mix/tasks/busybody.install.ex  # REWRITTEN as Igniter.Mix.Task (was regex)
```

### Coupling

`comn.bootstrap` references busybody by **path string** (opt-in, `--with-busybody`,
on by default). This is dev-tooling coupling only — comn's *runtime* code stays
ignorant of busybody. Only the bootstrap convenience knows busybody exists.

### Why the bootstrap task exists (path-dep wrinkle)

Igniter's native `mix igniter.install <pkg>` is Hex-oriented (adds
`{:pkg, "~> x"}` and runs the installer). comn and busybody are **local path
deps**, so we can't lean on it directly. `comn.bootstrap` does the equivalent for
path deps: add both path deps, fetch/compile, then compose the installers.

## Components

### 1. `mix comn.install`

`Igniter.Mix.Task`. Idempotent. Flags:

```text
mix comn.install
  --path ../comn        # path dep source (default ../comn)
  --git URL             # use a git dep instead of a path dep
  --name NAME           # app name for generated artifacts (default: OTP app)
  --no-context-plug     # skip generating + wiring the Contexts boundary plug
  --no-error-registry   # skip generating the starter error registry
```

Steps, in order:

1. **Dep** — add `{:comn, path: "../comn"}` to `mix.exs`, **all envs** (comn is a
   runtime foundation, not `only: :dev`). Skipped if already present.
2. **Context boundary plug** (unless `--no-context-plug`) — comn ships no Plug, so
   generate `lib/<app>_web/plugs/context.ex`. The plug calls
   `Comn.Contexts.new(request_id: ..., ...)` per request, pulling the request id
   from `Logger.metadata`/`conn`. Insert `plug <App>Web.Plugs.Context` into the
   router's `:browser` and `:api` pipelines (whichever exist) via Igniter's
   router helpers. Skipped cleanly if already wired.
3. **Error registry** (unless `--no-error-registry`) — generate
   `lib/<app>/errors.ex` (domain-level, not web-level) using
   `use Comn.Errors.Registry`, containing one **commented** `register_error/3`
   example so it compiles empty and demonstrates the pattern.
4. **Notice** — print next steps: `mix deps.get`; pointers to the
   `@behaviour Comn`, contexts, and registry patterns.

Judgment calls (locked):

- Plug lives in the **host app**, not comn — comn keeps a clean dep graph (no
  Phoenix/Plug dep).
- Error registry module defaults to **`lib/<app>/errors.ex`** (domain concern).

comn's API surface used here (verified):

- `Comn.Contexts.new/0,1`, `put/2`, `fetch/1`, `with_context/2`
- `use Comn.Errors.Registry` + `register_error/3`
- `Comn.Supervisor` self-starts via the OTP application — **no supervision wiring
  needed** for comn itself.

### 2. `mix busybody.install` (rewritten)

Replaces busybody's current ~241-line hand-rolled regex task with an
`Igniter.Mix.Task`. **Observable behavior preserved exactly**; only the mechanism
changes (Igniter AST instead of regex/line counting).

Flags preserved: `--name`, `--path`, `--git`.

Steps:

1. **Dep** — `{:busybody, path: "../busybody", only: :dev}` (still dev-only —
   busybody is a dev directory service).
2. **Supervision wiring** — add `Busybody.Client` to the host supervision tree,
   **still gated by `Code.ensure_loaded?/1`** so prod/test compile without the
   dep. Reproduce the existing shape: an `ensure_loaded?`-guarded helper returning
   `[{Busybody.Client, name: ..., endpoint: <App>Web.Endpoint}]`, inserted **after
   the endpoint** in the children list. Igniter makes the ordering and helper
   injection robust instead of regex-dependent.
3. **Notice** — same next-steps output (deps.get; start busybody; visit `:5150`).

Consequences (accepted):

- busybody gains an **`igniter` dep** (installer composability). Runtime untouched.
- The **old regex task is deleted**, not kept alongside. Single source of truth;
  its behavior is fully subsumed.

### 3. `mix comn.bootstrap` (combined command)

`Igniter.Mix.Task`. The single command run in a host app. Lives in comn.

```text
mix comn.bootstrap
  --with-busybody / --no-busybody   # install busybody too (default: on)
  --comn-path ../comn
  --busybody-path ../busybody
  --name NAME                       # pass-through
  --no-context-plug                 # pass-through to comn.install
  --no-error-registry               # pass-through to comn.install
```

Sequencing (the honest path-dep flow):

1. **Add both path deps** to `mix.exs` (comn all-envs; busybody `only: :dev`) via
   Igniter; write.
2. **`mix deps.get` + `mix deps.compile`** so both installer tasks become loadable.
3. **Compose installers:**
   - Happy path (both deps already compiled when bootstrap starts): compose
     in-process — `Igniter.compose_task("comn.install", ...)` +
     `compose_task("busybody.install", ...)`. One Igniter run, one diff.
   - Cold-start fallback (tasks not yet loadable): re-invoke mix as a subprocess
     after step 2, exactly as `igniter.install` does.
   - Either way: **one command** for the user; the command never fails merely
     because deps weren't pre-compiled.
4. **Single summary** — deps added, artifacts generated, next steps.

## Data Flow

```text
mix comn.bootstrap
  -> Igniter.Project.Deps.add_dep {:comn, path}     (mix.exs)
  -> Igniter.Project.Deps.add_dep {:busybody, path, only: :dev}  (mix.exs)
  -> deps.get / deps.compile
  -> compose comn.install
       -> add_dep (noop, present)
       -> create lib/<app>_web/plugs/context.ex
       -> patch router pipelines (:browser, :api)
       -> create lib/<app>/errors.ex
  -> compose busybody.install
       -> add_dep (noop, present)
       -> patch application.ex (busybody_children/0 + ++ in child list)
  -> print summary
```

## Error Handling

- **Not a Phoenix app / no router** — context-plug wiring is skipped with a
  warning, not a hard failure (the dep + registry still apply). A plain
  `application.ex` without a router still gets busybody's supervision wiring.
- **Missing `mix.exs` deps list** — Igniter surfaces a clear error; we do not
  silently no-op.
- **Already wired** — every step diffs first (Igniter) and is a clean no-op when
  the artifact/patch is already present. Re-running `comn.bootstrap` is safe.
- **`deps.get`/`deps.compile` failure during bootstrap** — abort with the
  underlying mix error; `mix.exs` changes are left in place so the user can fix
  and re-run (idempotent).

## Testing

Use **Igniter's `test_project` / `assert_has_patch` / `assert_creates`** helpers —
in-memory synthetic Phoenix projects, no disk app required. Coverage:

`comn.install`:

- adds the comn dep (all-envs, not `only: :dev`)
- generates the context plug and wires `:browser` + `:api` pipelines
- generates the error registry at `lib/<app>/errors.ex`
- `--no-context-plug` / `--no-error-registry` suppress their pieces
- idempotent: second run is a no-op
- non-Phoenix project: dep + registry apply, plug wiring skipped with warning

`busybody.install`:

- adds the busybody dep `only: :dev`
- injects `busybody_children/0` guarded by `Code.ensure_loaded?/1`
- appends `++ busybody_children()` after the endpoint in the child list
- `--name`, `--path`, `--git` honored
- idempotent: second run is a no-op

`comn.bootstrap`:

- adds both deps with correct env scoping
- composes both installers (in-process happy path)
- `--no-busybody` installs comn only
- pass-through flags reach `comn.install`

## Implementation Order

1. Add `igniter` dep to comn and busybody.
2. `comn.install` (Igniter task) + tests.
3. `busybody.install` rewrite (Igniter task), delete old regex task, + tests.
4. `comn.bootstrap` (compose) + tests.
5. Update both READMEs to document the new installers and `mix comn.bootstrap`.

## Follow-on (not this spec)

- Scaffold the `updater` Phoenix app; run `mix comn.bootstrap` against it as the
  first real consumer and an end-to-end fixture.
