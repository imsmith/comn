# Comn.Secrets.GPG — Design

**Date:** 2026-11-03
**Status:** Implemented (2026-11-04; plan `docs/superpowers/plans/2026-11-03-secrets-gpg.md`)
**Repo:** `comn`
**Out of scope:** the host-side credentials broker and its `gpg-agent`
adapter (see `~/.claude/memory/credentials-broker-spec.md`); a pure-Elixir
OpenPGP implementation.

## Problem

`Comn.Secrets` has two backends: `Local` (ChaCha20-Poly1305 via `:crypto`)
and `Vault` (HashiCorp Transit). Neither produces output that anything
outside Comn can read. Files encrypted for operators, for other hosts, or
for long-term archive need to be OpenPGP: decryptable with `gpg -d`, signed
so the recipient can check provenance, and stored wherever a Comn Repo
shape already puts things.

## Goals

- A third `Comn.Secrets` backend, `Comn.Secrets.GPG`, following every
  convention the existing backends follow: `@behaviour Comn` and
  `@behaviour Comn.Secrets`, `lock/unlock/wrap/unwrap`, `Key`/`LockedBlob`
  structs, registered `secrets/*` `ErrorStruct` errors, `look/recon/choices/act`.
- Public-key (recipient) encryption, symmetric (passphrase) encryption, and
  optional signing on lock with signature verification on unlock.
- Raw OpenPGP output, armored or binary by option. `gpg -d` on the stored
  bytes works without Comn.
- Put a locked blob into any `Comn.Repo` shape and fetch it back.

## Non-goals

- Key generation, import, export, trust management, or keyring
  administration. Keys live in a GnuPG homedir that something else manages.
- Passphrase prompting. No pinentry UI is driven from Elixir.
- Streaming encryption of large files. Blobs are in-memory binaries, same
  as the other backends.
- RSA/ECDSA support in `Local`. Unchanged.

## Anti-goals

- Passphrases or plaintext on argv, in logs, in error messages, or on disk.
- Reimplementing OpenPGP. If `gpg` cannot do it from the command line, the
  backend does not do it.
- A second key-struct shape. `:gpg` is an algorithm on the existing `Key`.

## Decisions (as decided by Ian)

1. **Engine:** shell out to the system `gpg` binary. The host's `gpg-agent`
   owns the keyring and any passphrase caching. No pure-Elixir OpenPGP.
2. **Key shape:** a new `:gpg` algorithm on `Comn.Secrets.Key`, not the
   Vault pattern of a dummy Ed25519 key with config in metadata.
3. **Modes:** recipient encryption, symmetric encryption, and signing.
4. **Output:** raw gpg output in `LockedBlob.encrypted`, armored or binary.
5. **Destinations:** any `Comn.Repo` shape.
6. **Tests:** throwaway `GNUPGHOME` per test, skip when no `gpg` binary.

## Design

### Key

`Comn.Secrets.Key` grows one algorithm, `:gpg`, with fingerprint byte
`0x04` in `@algorithm_bytes` and `algorithm_from_fingerprint/1`.

Recipient mode:

```elixir
%Key{
  algorithm: :gpg,
  public: <<fingerprint::binary>>,   # 20 (v4) or 32 (v5) raw bytes, the primary key fingerprint
  private: nil,
  metadata: %{
    homedir: "/path/to/gnupghome",   # optional; default is gpg's own default
    recipients: ["<hex fingerprint>", ...],  # optional extra recipients
    sign: true | "<hex fingerprint>", # optional; true signs with `public`
    armor: true | false               # optional, default true
  }
}
```

`public` is the raw fingerprint bytes so `Key.fingerprint/1` (BLAKE2b of
`public`) stays meaningful and `key_hint` on the blob identifies the key
without exposing it. The hex form is derived for the command line.

Symmetric mode:

```elixir
%Key{
  algorithm: :gpg,
  public: "backup-2026",             # a label; any non-empty binary, used only for key_hint
  private: "the passphrase",         # the secret material, same slot Local uses
  metadata: %{mode: :symmetric, homedir: ..., armor: ..., sign: ...}
}
```

`public` is a caller-chosen label, never derived from the passphrase, so
`key_hint` is not an offline dictionary target. (My call.)

`Comn.Secrets.Utils.validate_key/1` gains two clauses:

- `:gpg`, no `mode: :symmetric`: `public` is a binary of 20 or 32 bytes,
  `private` is nil. Anything else is `secrets/invalid_key`.
- `:gpg`, `mode: :symmetric`: `public` is a non-empty binary, `private` is a
  non-empty binary. Anything else is `secrets/invalid_key`.

Config errors that are not key-shape errors (a `homedir` that does not
exist, a `recipients` entry that is not hex, a `sign` fingerprint that is
not hex) are `secrets/invalid_gpg_config`.

### LockedBlob

```elixir
%LockedBlob{
  cipher: :gpg,
  encrypted: <<raw gpg output>>,     # armored text or binary packets
  tag: nil,
  nonce: nil,
  key_hint: Key.fingerprint(key),
  metadata: %{
    created_at: iso8601,
    algorithm: :gpg,
    mode: :recipient | :symmetric,
    armor: boolean,
    signed: boolean,
    recipients: ["<hex fingerprint>", ...]   # recipient mode: every recipient, key.public first
  }
}
```

`LockedBlob.cipher` type gains `:gpg`. `tag` and `nonce` are nil: OpenPGP
carries its own MDC/AEAD and session-key material inside the packets.
`metadata` is informational and is not authenticated; the OpenPGP packets
are the authenticated artifact. The moduledoc says so.

### Comn.Secrets.GPG

```elixir
@behaviour Comn
@behaviour Comn.Secrets

lock(blob, key)       # {:ok, %LockedBlob{cipher: :gpg}} | {:error, ErrorStruct}
unlock(locked, key)   # {:ok, plaintext} | {:error, ErrorStruct}
wrap(blobs, key)      # Utils.wrap(__MODULE__, ...)
unwrap(locked, key)   # Utils.unwrap(__MODULE__, ...)
put(locked, repo, handle, opts)   # see Repo destinations
fetch(repo, handle, opts)         # see Repo destinations
look/0, recon/0, choices/0, act/1
```

**lock/2**, recipient mode, runs:

```text
gpg --batch --yes --quiet --no-tty
    [--homedir H]
    --trust-model always
    [--armor]
    --encrypt --recipient <FPR> [--recipient <FPR> ...]
    [--sign --local-user <FPR>]
    --status-file <tmp>
```

with the plaintext on stdin and the ciphertext from stdout.
`--trust-model always` because the recipient was named by full fingerprint
in the `Key`; that is the trust decision. (My call.)

**lock/2**, symmetric mode, runs:

```text
gpg --batch --yes --quiet --no-tty [--homedir H]
    --pinentry-mode loopback --passphrase-fd 0
    [--armor] --symmetric [--sign --local-user <FPR>]
    --status-file <tmp>
```

with `passphrase <> "\n" <> plaintext` on stdin. gpg 2.4 reads the first
line of fd 0 as the passphrase and the remainder as data. Verified on this
host (gpg 2.4.7). The builder must keep the round-trip test that proves it.
The passphrase is never on argv, never in a file.

**unlock/2** runs:

```text
gpg --batch --quiet --no-tty [--homedir H]
    [--pinentry-mode loopback --passphrase-fd 0]   # symmetric only
    --decrypt --status-file <tmp>
```

with (`passphrase <> "\n"` in symmetric mode, then) the ciphertext on
stdin, plaintext from stdout.

**Key-hint gate.** The other backends refuse before decrypting when
`locked.key_hint` does not match the key. GPG blobs can have several
recipients and can arrive without a hint (raw fetch), so the gate is:

- `locked.key_hint` nil: no gate; gpg decides (`NO_SECKEY` is `secrets/wrong_key`).
- otherwise pass if `Key.fingerprint_matches?(locked.key_hint, key)`, or if
  the key is recipient-mode and its hex fingerprint is in
  `locked.metadata.recipients`. Anything else is `secrets/wrong_key`.
  (My call.)

**Signature policy on unlock.** If `key.metadata.sign` is set or
`locked.metadata.signed` is true, the status file must contain a `VALIDSIG`
line whose fingerprint equals the expected signer (`key.metadata.sign`
when it is a fingerprint, else `key.public` in recipient mode); otherwise
`secrets/authentication_failed`. A blob that is signed but whose key does
not demand a signature is still verified when gpg verifies it, and a
`BADSIG` is `secrets/authentication_failed` regardless. An unsigned blob
with a key that does not demand signing is fine.

**Process boundary.** A BEAM port cannot close the child's stdin on its
own, and gpg reads stdin to EOF, so run through the shell with the byte
count as the only argv addition:

```text
/bin/sh -c 'head -c "$1" | exec gpg ...' sh <N>
```

where `N` is `byte_size(passphrase_line <> plaintext)`. Open with
`Port.open({:spawn_executable, "/bin/sh"}, [:binary, :exit_status, :use_stdio, :stream, args: ...])`,
`Port.command/2` the input, collect stdout until `{:exit_status, n}`.
`System.cmd/3` cannot feed stdin, so it is not an option. (My call,
after the builder check found the `:eof` mechanism I first wrote does not
exist.) stderr is not captured (gpg writes
nothing secret there and `--quiet` keeps it short); machine-readable status
goes through `--status-file` in a private tmp dir created with mode `0700`
and removed in an `after` block. The status file carries key ids and
result codes, never key material or plaintext. (My call on `--status-file`
over `--status-fd`: ports expose only stdin/stdout.)

The builder may find a cleaner way to drive stdin on a port; the
constraints are: plaintext and passphrase never on argv, never on disk,
stdout kept binary-clean.

**Signing in symmetric mode.** `sign: true` has no fingerprint to sign
with (`public` is a label), so it is `secrets/invalid_gpg_config`; a hex
fingerprint is required. `VALIDSIG` is compared on its primary-key
fingerprint field so subkey signatures still match `key.public`. (My call.)

**gpg binary.** `System.find_executable("gpg")`, overridable by
`key.metadata.gpg_path`. Missing binary is `secrets/gpg_unavailable`.

**Timeout.** 30 seconds per gpg invocation (`key.metadata.timeout_ms`
overrides), after which the port is closed and the result is
`secrets/gpg_error`. The status file lives in a `0700` directory
`comn_gpg_status_<unique>` under the system tmp dir, removed after every
call. gpg-agent prompting for a
passphrase it cannot get in `--batch` mode fails fast on its own; the
timeout is a backstop. (My call.)

### Errors

New codes in `Comn.Secrets.Errors`:

| Code | Category | When |
|---|---|---|
| `secrets/invalid_gpg_config` | `:validation` | bad `homedir`, non-hex fingerprint in `recipients` or `sign`, bad `gpg_path` |
| `secrets/gpg_unavailable` | `:network` | no `gpg` executable found or the port could not spawn |
| `secrets/gpg_error` | `:internal` | gpg exited non-zero with no more specific mapping, or timed out |

Existing codes reused, mapped from `--status-file` lines:

| Status line | Error |
|---|---|
| `DECRYPTION_FAILED`, `NO_SECKEY`, `BAD_PASSPHRASE`, `MISSING_PASSPHRASE` | `secrets/wrong_key` |
| `BADSIG`, `ERRSIG`, `NO_PUBKEY`, missing `VALIDSIG` when required | `secrets/authentication_failed` |
| `NODATA`, `UNEXPECTED`, `FAILURE ... 'Invalid packet'`-class parse errors | `secrets/invalid_ciphertext` |
| `INV_RECP`, `KEYEXPIRED`, `KEYREVOKED` | `secrets/invalid_gpg_config` |

`secrets/invalid_ciphertext`'s message currently says "Vault returned
ciphertext that could not be decoded"; reword to backend-neutral text.
Error messages never include the blob, the passphrase, or the status
file contents beyond the status keyword.

### Repo destinations

A locked GPG blob has two useful shapes on disk: the raw OpenPGP bytes
(for `gpg -d`), and a Comn event carrying the `LockedBlob` (for any shape,
per ADR-0001). `Comn.Secrets.GPG.put/4` and `fetch/3` cover both:

```elixir
# raw: only Comn.Repo.File; writes locked.encrypted via set(f, value: ...)
{:ok, f} = GPG.put(locked, Comn.Repo.File, f, as: :raw)

# event (default): any shape; set(h, event: %{type: :secrets_locked, topic: "comn.secrets", data: locked})
{:ok, event_id, :ok}      = GPG.put(locked, Comn.Repo.Table, t, [])
{:ok, event_id, {:ok, f}} = GPG.put(locked, Comn.Repo.File, f, [])   # one event line appended

# fetch
{:ok, locked} = GPG.fetch(Comn.Repo.File, f, as: :raw)     # read/1 the file, rebuild a LockedBlob
{:ok, locked} = GPG.fetch(repo, h, id: event_id)           # get(h, id: ...) then .data
```

The event is built with `Comn.Events.EventStruct.new/1`, which mints the
id, so `put/4` in event form returns `{:ok, event_id, set_result}`: the id
the caller needs for `fetch`, plus the shape's own `set/2` result
unchanged (`:ok`, or `{:ok, new_handle}` for shapes that rebind). Raw form
returns `{:ok, new_handle}`. Topic is `"comn.secrets"`. (My call; the
builder check found the id had no way back to the caller.)
Raw mode on a non-File shape is `secrets/invalid_gpg_config`. A raw fetch
rebuilds the `LockedBlob` with `metadata.armor` detected from the leading
`-----BEGIN PGP MESSAGE-----` and `mode`/`signed` unknown (nil); unlock
does not need them. (My call: `put/fetch` live on the GPG module because
raw interop is the GPG-specific part. If a later backend wants the event
form, lift the event half into `Comn.Secrets`.)

The event `type` is `:secrets_locked` and `data` is the `LockedBlob` struct;
the event line encoding (`term_to_binary` + base64) already carries structs.

### Introspection

```elixir
look  -> "Secrets.GPG — OpenPGP via the gpg binary; recipient or symmetric, optional signing"
recon -> %{backend: :gpg, requires: [:gpg_binary], key_management: :keyring,
           modes: [:recipient, :symmetric], signing: true, type: :implementation}
choices -> %{operations: ["lock", "unlock", "wrap", "unwrap", "put", "fetch"],
             config: ["mode", "homedir", "recipients", "sign", "armor", "gpg_path", "timeout_ms"]}
act -> same four clauses as Local/Vault plus :put and :fetch
```

`Comn.Secrets.recon/0` and `choices/0` list `GPG`/`"GPG"` and `:gpg`.

### Tests

`test/comn/secrets/gpg_test.exs`, `@moduletag :gpg`. The module skips
entirely (`@moduletag skip: "gpg not found"`) when
`System.find_executable("gpg")` is nil. Each test gets a fresh `GNUPGHOME`
under `System.tmp_dir!()`, mode `0700`, with a key made by:

```text
gpg --homedir H --batch --passphrase '' --quick-gen-key "Comn Test <test@comn.invalid>" default default never
```

and the primary fingerprint parsed from `gpg --homedir H --with-colons --list-keys` (`fpr:` record). The homedir is removed in `on_exit`; the
builder must also kill the agent gpg starts in that homedir
(`gpgconf --homedir H --kill gpg-agent`) so the suite leaves no daemons.

`Comn.Secrets.SecurityTestCase` is Ed25519-specific (nonce uniqueness, key
sizes) and is not used. The GPG test covers the same ground in its own
words:

- key validation: wrong fingerprint length, private set in recipient mode,
  missing passphrase in symmetric mode, non-hex `sign`.
- recipient round trip, armored and binary; `gpg -d` on `locked.encrypted`
  from the shell returns the plaintext (the interop check).
- symmetric round trip with the passphrase on fd 0.
- signed round trip; `VALIDSIG` checked; a blob signed by another key is
  `secrets/authentication_failed`; an unsigned blob with `sign` demanded is
  `secrets/authentication_failed`.
- wrong key: a second homedir's key cannot unlock (`secrets/wrong_key`);
  wrong passphrase (`secrets/wrong_key`).
- tampering: a flipped byte in the packets is `secrets/authentication_failed`
  or `secrets/invalid_ciphertext`, never `{:ok, _}`.
- wrap/unwrap through `Utils`.
- `put`/`fetch` raw to `Comn.Repo.File` (`:local`, root-confined) and event
  form to `Comn.Repo.File` and `Comn.Repo.Table`; a raw-fetched blob
  (no `key_hint`) unlocks; a second recipient's key unlocks a
  multi-recipient blob.
- a `gpg_path` that does not exist is `secrets/invalid_gpg_config`; no gpg
  on PATH at all is `secrets/gpg_unavailable` (not exercised, the suite
  skips without gpg).

Existing test suites: `test/comn/secrets/local_test.exs` and the
`SecurityTestCase` must stay green; `Key.algorithm_from_fingerprint` gets a
`0x04` case in whichever test covers it.

### Docs

- README Secrets section: one paragraph and one example for GPG; the status
  table row for Secrets; the file layout list.
- `Comn.Secrets` moduledoc: add `:gpg` to the implementation requirements
  (key validation bullet) and `GPG` to the implementations list.
- CHANGELOG entry under Unreleased.
- Credo `--strict`, `mix vet`, `mix deps.audit`, sobelow stay green. No
  `credo:disable` for the port spawn; if a check fires on `Port.open` with
  a computed path, fix it (validate `gpg_path` is absolute and executable)
  rather than annotate.

## Left to the builder

- Exact port handling (how stdout is accumulated, exit handling), within
  the constraints above.
- Status-file parsing structure.
- Whether `gpgconf --kill` runs per test or once per module.
- Test helper layout (`test/support/gpg_helpers.ex` or inline).
