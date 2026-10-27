# Changelog

Notable changes to comn. Newest first. Earlier history is in git.

## 0.7.0 — 2026-10-27

One handle, one lifecycle, every shape a facade; paths confined to a root;
analyzer findings fixed rather than suppressed; three Credo checks that
ship with the library.

### Breaking

- **`Comn.Repo.File.open/2` requires a root.** The `:local` backend needs
  `root:`; `:nfs` keeps `mount:`. Both resolve every path through
  `Comn.Repo.File.Root` and refuse one that lands outside with
  `repo.file/outside_root`. A relative path is joined to the root, an
  absolute path must already be under it. `Comn.Repo.File.Local.open/2`
  has the same requirement; `act/1` takes `root:` too. NFS returns the
  error struct where it used to raise `ArgumentError`.
- **One handle struct.** `Comn.Repo.Table.Handle`, `Queue.Handle`,
  `Bus.Handle`, `Stream.Handle`, and `Merkel.Handle` are replaced by
  `Comn.Repo.Handle` with a `shape` field and a `meta` map. Pattern-match
  on `%Comn.Repo.Handle{shape: Comn.Repo.Stream}`. A queue's discipline is
  `meta.discipline`.
- **Graph error codes are `repo.graphs/*`.** `repo.graph/missing_key`,
  `unknown_query_type`, `zone_not_found`, and `unreachable` are renamed so
  the prefix matches the shape module.
- **Backend modules must declare their behaviour.** A custom backend
  passed to any facade's `open/2` is accepted only if it declares
  `@behaviour Comn.Repo.<Shape>.Backend`. Probing for one representative
  function is gone.
- **`Comn.Repo.Column.ETS.create/1`** reports `repo.column/already_exists`
  on a duplicate name, not `not_found`. The struct is now `%{name: atom}`;
  `rows_table` and `meta_table` are gone, one ETS table holds both.
- **Ecto repo config files are data.** `ecto: "path/to/repo.exs"` is parsed
  as literals (atoms, strings, numbers, module names, lists, tuples, maps)
  and never evaluated. A file containing a call expression is refused with
  `repo.table/invalid_opts`.
- **Vault backend error codes.** A non-200 from Vault is
  `secrets/vault_error`; transport failure is `secrets/vault_unavailable`.
  Previously a non-200 was relabelled `vault_unavailable` by the caller.

### Added

- `Comn.Repo.Handle` and `Comn.Repo.Lifecycle`: `open/3`, `close/1`,
  `drop/1`, `resolve_backend/2`, and `rebind/2` for value shapes. Every
  facade delegates to them; `backends/0` is an optional `Comn.Repo`
  callback.
- `Comn.Repo.Column`, `Comn.Repo.File`, `Comn.Repo.Graphs`, and
  `Comn.Repo.Batch` are facades with fungible backends, like Table, Queue,
  Bus, Stream, and Merkel already were. Backend contracts live at
  `<Shape>.Backend`; private adapters (Column.ETSAdapter, Batch.MemAdapter,
  Graphs.GraphAdapter, File.Adapter) wrap the existing implementation
  modules, which keep their public surface.
- `Comn.Repo.File.Root`: path confinement shared by the file backends.
- `Comn.Repo.decode_term/1`: the one place a Comn backend turns external
  term format back into a term, with `Plug.Crypto.non_executable_binary_to_term/2`
  (`:safe`, and no funs, pids, ports, or references). `plug_crypto` is a
  new runtime dependency.
- `Comn.Repo.events_in/1`: the `as: :events` view over keyed pairs.
- `Comn.Secrets.Utils`: `validate_key/1`, `wrap/3`, `unwrap/3`, shared by
  the Local and Vault backends.
- **Credo checks** in `Comn.Credo`: `BareErrorAtom` (every error is an
  `ErrorStruct`), `SecretFromEnv` (secret-looking names read from env or
  config belong behind `Comn.Secrets`), `RawShell` (`System.cmd`,
  `System.shell`, `:os.cmd`, `Port.open` belong behind `Comn.Repo.Cmd`).
  `credo` is an optional dependency; consumers list the checks in
  `.credo.exs`.
- Error codes: `repo.column/invalid_opts`, `repo.column/already_exists`,
  `repo.batch/invalid_opts`, `repo.graphs/invalid_opts`,
  `repo.file/invalid_opts`, `repo.file/outside_root`.
- `Comn.Repo.Batch.close/1` flushes pending items before releasing;
  `drop/1` discards them.

### Fixed

- The SQLite queue backend decoded payloads without `:safe` (ISSUES.md,
  2026-10-13). All decoding now goes through `Comn.Repo.decode_term/1`.
- `Comn.Discovery` did not preload `Comn.Repo.Stream`, `Bus`, or `Merkel`,
  so they were missing from `by_type(:facade)` until first use.
- README examples for Batch and Column called functions that did not exist.

### Tooling

- `mix credo --strict` is clean, test files included.
- `sobelow`, `mix_audit`, and `vet_cli` are dev/test dependencies.
  `mix sobelow` reports 13 low-confidence traversal findings, all on
  confined or operator-configured paths; the check fires on any `File`
  call with a non-literal path. `mix deps.audit` is clean. `vet_cli` is a
  path dependency on a local checkout until an exponential walk in
  `vet_core` 0.1.0 is fixed upstream.
- `Comn.StreamConformance` is two macros, `Log` and `Sink`, composed by
  the umbrella.

### Upgrading from 0.6.x

1. Add `root:` to every `Comn.Repo.File.open/2` and `File.Local.open/2`
   call. If callers pass absolute paths, the root is the directory those
   paths must live under.
2. Replace `%Comn.Repo.<Shape>.Handle{}` matches with
   `%Comn.Repo.Handle{shape: Comn.Repo.<Shape>}`; replace `h.discipline`
   with `h.meta.discipline`.
3. Grep for `repo.graph/` and change to `repo.graphs/`.
4. Add `@behaviour Comn.Repo.<Shape>.Backend` to any custom backend.
5. If a Column store's struct fields were read directly, use `describe/1`.
6. If an `.exs` repo config computed anything, make it a literal.
