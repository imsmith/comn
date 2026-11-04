# Comn.Secrets.GPG Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A third `Comn.Secrets` backend that drives the system `gpg` binary for recipient, symmetric, and signed OpenPGP encryption, and puts the result into any `Comn.Repo` shape.

**Architecture:** One new module, `Comn.Secrets.GPG`, with the same four callbacks as `Local` and `Vault`, plus `put/4` and `fetch/3`. gpg runs under a port via `/bin/sh -c 'head -c "$1" | exec gpg ...'` with plaintext (and passphrase line) on stdin, ciphertext on stdout, machine status in a `--status-file` inside a private tmp dir. `Key` gains the `:gpg` algorithm; `Utils.validate_key/1` gains two clauses; `Secrets.Errors` gains three codes.

**Tech Stack:** Elixir, Erlang ports, GnuPG 2.4 (`gpg`, `gpgconf`), ExUnit.

**Spec:** `docs/superpowers/specs/2026-11-03-secrets-gpg-design.md`

## Global Constraints

- Every error is a `Comn.Errors.ErrorStruct` built with `Comn.Errors.Registry.error!/1,2` from a code registered in `Comn.Secrets.Errors`. No bare atoms.
- Passphrases and plaintext never appear on argv, in a file, in a log line, or in an error message. Only the byte count goes on argv.
- `mix credo --strict`, `mix compile --warnings-as-errors`, `mix vet`, `mix deps.audit`, `mix sobelow` stay green. No `credo:disable` or analyzer skip comments; fix the code.
- Tests are code: same Credo rules apply under `test/`.
- Every gpg invocation: `--batch --yes --quiet --no-tty`, `--homedir` only when `key.metadata.homedir` is set, 30 second timeout.
- The gpg binary is `key.metadata.gpg_path` or `System.find_executable("gpg")`; `gpg_path` must be an absolute path to an executable file, else `secrets/invalid_gpg_config`.
- `GNUPGHOME` tmp dirs in tests are mode `0700`, removed in `on_exit`, and their agent is killed with `gpgconf --homedir H --kill gpg-agent`.
- Config/data files: none introduced. No YAML, no JSON.

## Review Focus

1. A symmetric passphrase containing a newline would be split by `--passphrase-fd 0`; it must be `secrets/invalid_key`, never silently truncated. (Task 1 test.)
2. An empty plaintext (`""`) must round-trip; `head -c 0` and gpg both accept it. (Task 3 test.)
3. Hex fingerprints in `recipients`/`sign` arrive in any case and sometimes with spaces; normalize to uppercase, no spaces, and reject anything not 40 or 64 hex chars. (Task 1 test.)
4. A raw-fetched blob must be detected as armored only when it starts with `-----BEGIN PGP MESSAGE-----`; binary packets starting with a byte that happens to be `-` are binary. (Task 7 test.)
5. gpg hanging (for example a key with a passphrase the agent cannot get) must end in `secrets/gpg_error` after the timeout, with the port closed and the tmp dir removed. (Task 3 test, using `gpg_path` pointed at a `sleep` wrapper.)

---

### Task 1: `:gpg` on Key, Utils, LockedBlob, Errors

**Files:**
- Modify: `lib/comn/secrets/key.ex` (`@type algorithm`, `@algorithm_bytes`, `algorithm_from_fingerprint/1`, moduledoc)
- Modify: `lib/comn/secrets/utils.ex` (`validate_key/1`)
- Modify: `lib/comn/secrets/locked_blob.ex` (`@type cipher`, moduledoc note that `:gpg` blobs have nil `tag`/`nonce` and unauthenticated metadata)
- Modify: `lib/comn/secrets/errors.ex`
- Create: `test/comn/secrets/gpg_key_test.exs` (no gpg binary needed)

**Interfaces:**
- Produces: `Key.algorithm() :: :ed25519 | :rsa_4096 | :ecdsa_p256 | :gpg`; fingerprint byte `0x04`; `Utils.validate_key/1` accepts the two `:gpg` shapes in the spec; `Utils.gpg_fingerprint_hex(binary) :: {:ok, String.t()} | {:error, ErrorStruct.t()}` (normalize: strip spaces, upcase, require 40 or 64 hex chars); error codes `secrets/invalid_gpg_config` (`:validation`), `secrets/gpg_unavailable` (`:network`), `secrets/gpg_error` (`:internal`).

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule Comn.Secrets.GPGKeyTest do
  use ExUnit.Case, async: true
  alias Comn.Errors.ErrorStruct
  alias Comn.Secrets.{Key, Utils}

  @fpr :crypto.strong_rand_bytes(20)

  test "fingerprint byte 0x04 round-trips" do
    key = %Key{algorithm: :gpg, public: @fpr}
    assert <<0x04, _::binary-16>> = Key.fingerprint(key)
    assert Key.algorithm_from_fingerprint(Key.fingerprint(key)) == :gpg
  end

  test "recipient key: 20- or 32-byte public, nil private" do
    assert :ok = Utils.validate_key(%Key{algorithm: :gpg, public: @fpr})
    assert :ok = Utils.validate_key(%Key{algorithm: :gpg, public: :crypto.strong_rand_bytes(32)})
    assert {:error, %ErrorStruct{code: "secrets/invalid_key"}} =
             Utils.validate_key(%Key{algorithm: :gpg, public: :crypto.strong_rand_bytes(16)})
    assert {:error, %ErrorStruct{code: "secrets/invalid_key"}} =
             Utils.validate_key(%Key{algorithm: :gpg, public: @fpr, private: "x"})
  end

  test "symmetric key: non-empty label and passphrase, no newline" do
    sym = %Key{algorithm: :gpg, public: "label", private: "pw", metadata: %{mode: :symmetric}}
    assert :ok = Utils.validate_key(sym)
    assert {:error, %ErrorStruct{code: "secrets/invalid_key"}} = Utils.validate_key(%{sym | private: nil})
    assert {:error, %ErrorStruct{code: "secrets/invalid_key"}} = Utils.validate_key(%{sym | private: ""})
    assert {:error, %ErrorStruct{code: "secrets/invalid_key"}} = Utils.validate_key(%{sym | public: ""})
    assert {:error, %ErrorStruct{code: "secrets/invalid_key"}} = Utils.validate_key(%{sym | private: "a\nb"})
  end

  test "gpg_fingerprint_hex normalizes and rejects" do
    assert {:ok, String.duplicate("AB", 20)} = Utils.gpg_fingerprint_hex("ab ab " <> String.duplicate("ab", 18))
    assert {:ok, String.duplicate("0F", 32)} = Utils.gpg_fingerprint_hex(String.duplicate("0f", 32))
    assert {:error, %ErrorStruct{code: "secrets/invalid_gpg_config"}} = Utils.gpg_fingerprint_hex("zz")
    assert {:error, %ErrorStruct{code: "secrets/invalid_gpg_config"}} = Utils.gpg_fingerprint_hex(String.duplicate("ab", 19))
  end

  test "new error codes are registered" do
    for code <- ~w(secrets/invalid_gpg_config secrets/gpg_unavailable secrets/gpg_error) do
      assert %ErrorStruct{code: ^code} = Comn.Errors.Registry.error!(code)
    end
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `mix test test/comn/secrets/gpg_key_test.exs`
Expected: FAIL (`Map.fetch!` on `@algorithm_bytes`, `invalid_key` for valid gpg keys, undefined `gpg_fingerprint_hex/1`, unregistered codes).

- [ ] **Step 3: Implement**

`key.ex`: add `gpg: 0x04` and the `0x04` clause; extend the type and the Fields/Fingerprints doc lines.
`utils.ex`: two `validate_key` clauses per spec (symmetric clause matches `metadata: %{mode: :symmetric}`; recipient clause is any other `:gpg`); `gpg_fingerprint_hex/1` using `String.replace(~r/\s/, "")`, `String.upcase/1`, and `Regex.match?(~r/\A[0-9A-F]{40}\z|\A[0-9A-F]{64}\z/, hex)`.
`errors.ex`: three `register_error` calls with the spec's categories; reword `secrets/invalid_ciphertext` to `"Ciphertext could not be decoded"`.
`locked_blob.ex`: `@type cipher :: :aes_gcm | :chacha20_poly1305 | :vault_transit | :gpg` and one doc paragraph.

- [ ] **Step 4: Run to verify it passes, plus existing suites**

Run: `mix test test/comn/secrets/ && mix credo --strict`
Expected: PASS, Credo clean.

- [ ] **Step 5: Commit**

```bash
git add lib/comn/secrets/key.ex lib/comn/secrets/utils.ex lib/comn/secrets/locked_blob.ex lib/comn/secrets/errors.ex test/comn/secrets/gpg_key_test.exs
git commit -m "feat(secrets): :gpg key algorithm, validation, and error codes"
```

---

### Task 2: Test support for throwaway GnuPG homedirs

**Files:**
- Create: `test/support/gpg_helpers.ex`
- Modify: `test/test_helper.exs` (add `:gpg` to `exclude` when `System.find_executable("gpg")` is nil, same pattern as `:vault_integration`)

**Interfaces:**
- Produces module `Comn.Secrets.GPGHelpers`:
  - `homedir!() :: Path.t()` creates `Path.join(System.tmp_dir!(), "comn_gpg_<unique>")` with `File.mkdir_p!` then `File.chmod!(dir, 0o700)`; registers `ExUnit.Callbacks.on_exit` that runs `gpgconf --homedir dir --kill gpg-agent` via `System.cmd/3` and then `File.rm_rf!/1`.
  - `gen_key!(homedir, name \\ "Comn Test <test@comn.invalid>") :: String.t()` runs `gpg --homedir H --batch --pinentry-mode loopback --passphrase "" --quick-gen-key NAME default default never` then `gpg --homedir H --with-colons --list-keys` and returns the first `fpr:` record's 10th field (the primary fingerprint, uppercase hex).
  - `recipient_key(homedir, fpr_hex, meta \\ %{}) :: Key.t()` returns `%Key{algorithm: :gpg, public: Base.decode16!(fpr_hex), metadata: Map.merge(%{homedir: homedir}, meta)}`.
  - `symmetric_key(passphrase, meta \\ %{}) :: Key.t()` returns `%Key{algorithm: :gpg, public: "label", private: passphrase, metadata: Map.merge(%{mode: :symmetric}, meta)}`.
  - `shell_decrypt!(homedir, ciphertext) :: binary()` writes `ciphertext` to a file inside `homedir`, runs `gpg --homedir H --batch --quiet --decrypt FILE` with `System.cmd/3`, asserts exit 0, returns stdout.

- [ ] **Step 1: Write the helper module and the test_helper line**

Implement as specified. `gen_key!` raises `RuntimeError` with gpg's output when exit status is non-zero.

- [ ] **Step 2: Write a smoke test proving the helper works**

Add to `test/comn/secrets/gpg_test.exs` (created here, grown in later tasks):

```elixir
defmodule Comn.Secrets.GPGTest do
  use ExUnit.Case
  @moduletag :gpg
  import Comn.Secrets.GPGHelpers
  alias Comn.Errors.ErrorStruct
  alias Comn.Secrets.{GPG, Key, LockedBlob}

  setup do
    home = homedir!()
    fpr = gen_key!(home)
    {:ok, home: home, fpr: fpr, key: recipient_key(home, fpr)}
  end

  test "helper generates a usable key", %{home: home, fpr: fpr} do
    assert String.length(fpr) in [40, 64]
    assert File.stat!(home).mode |> Bitwise.band(0o777) == 0o700
  end
end
```

- [ ] **Step 3: Run to verify it passes and leaves no agent behind**

Run: `mix test test/comn/secrets/gpg_test.exs && pgrep -af "gpg-agent.*comn_gpg_" ; ls /tmp | grep comn_gpg_`
Expected: PASS; `pgrep` prints nothing; `ls` prints nothing.

- [ ] **Step 4: Commit**

```bash
git add test/support/gpg_helpers.ex test/test_helper.exs test/comn/secrets/gpg_test.exs
git commit -m "test(secrets): throwaway GnuPG homedir helpers"
```

---

### Task 3: `Comn.Secrets.GPG` recipient lock/unlock through a port

**Files:**
- Create: `lib/comn/secrets/gpg.ex`
- Test: `test/comn/secrets/gpg_test.exs`

**Interfaces:**
- Consumes: Task 1 (`validate_key`, `gpg_fingerprint_hex`, error codes), Task 2 helpers.
- Produces:
  - `GPG.lock(binary(), Key.t()) :: {:ok, LockedBlob.t()} | {:error, ErrorStruct.t()}`
  - `GPG.unlock(LockedBlob.t(), Key.t()) :: {:ok, binary()} | {:error, ErrorStruct.t()}`
  - private `run(key :: Key.t(), args :: [String.t()], stdin :: binary()) :: {:ok, stdout :: binary(), status :: [String.t()]} | {:error, ErrorStruct.t()}`: resolves the binary, makes a `0700` tmp dir, appends `--status-file <dir>/status`, spawns `/bin/sh` with args `["-c", "n=$1; shift; head -c \"$n\" | exec \"$@\"", "sh", "<N>", gpg_path | args]`, writes `stdin` with `Port.command/2`, collects `{port, {:data, chunk}}` until `{port, {:exit_status, n}}` or 30_000 ms; reads and splits the status file; removes the dir in `after`.
  - private `status_error(status :: [String.t()]) :: ErrorStruct.t()` implementing the spec's status-line table; default `secrets/gpg_error`.
  - private `common_args(key) :: [String.t()]` = `["--batch", "--yes", "--quiet", "--no-tty"] ++ homedir args`.
  - private `recipient_args(key) :: {:ok, [String.t()]} | {:error, ErrorStruct.t()}` = `--trust-model always`, `--armor` unless `metadata.armor == false`, `--encrypt`, `--recipient <HEX>` for `key.public` then each of `metadata.recipients` (each through `gpg_fingerprint_hex`).
  - `LockedBlob` fields per spec; `metadata.recipients` is the full uppercase hex list, `key.public` first.
  - Key-hint gate as in the spec, private `hint_ok?(LockedBlob.t(), Key.t()) :: boolean()`.

- [ ] **Step 1: Write the failing tests** (append to `gpg_test.exs`)

```elixir
describe "recipient mode" do
  test "armored round trip and gpg -d interop", %{key: key, home: home} do
    assert {:ok, %LockedBlob{cipher: :gpg, tag: nil, nonce: nil} = locked} = GPG.lock("hello", key)
    assert String.starts_with?(locked.encrypted, "-----BEGIN PGP MESSAGE-----")
    assert locked.metadata.armor == true
    assert locked.metadata.mode == :recipient
    assert locked.metadata.signed == false
    assert locked.key_hint == Key.fingerprint(key)
    assert {:ok, "hello"} = GPG.unlock(locked, key)
    assert shell_decrypt!(home, locked.encrypted) == "hello"
  end

  test "binary output", %{key: key} do
    key = %{key | metadata: Map.put(key.metadata, :armor, false)}
    assert {:ok, locked} = GPG.lock("hello", key)
    refute String.starts_with?(locked.encrypted, "-----BEGIN")
    assert locked.metadata.armor == false
    assert {:ok, "hello"} = GPG.unlock(locked, key)
  end

  test "empty plaintext round-trips", %{key: key} do
    assert {:ok, locked} = GPG.lock("", key)
    assert {:ok, ""} = GPG.unlock(locked, key)
  end

  test "extra recipient can unlock", %{key: key, home: home} do
    fpr2 = gen_key!(home, "Second <two@comn.invalid>")
    key = %{key | metadata: Map.put(key.metadata, :recipients, [String.downcase(fpr2)])}
    assert {:ok, locked} = GPG.lock("hello", key)
    assert locked.metadata.recipients == [Base.encode16(key.public), fpr2]
    assert {:ok, "hello"} = GPG.unlock(locked, recipient_key(home, fpr2))
  end

  test "wrong key is secrets/wrong_key", %{key: key} do
    other_home = homedir!()
    other = recipient_key(other_home, gen_key!(other_home))
    assert {:ok, locked} = GPG.lock("hello", key)
    assert {:error, %ErrorStruct{code: "secrets/wrong_key"}} = GPG.unlock(locked, other)
    # same homedir, no hint: gpg decides
    assert {:error, %ErrorStruct{code: "secrets/wrong_key"}} =
             GPG.unlock(%{locked | key_hint: nil}, %{other | metadata: key.metadata})
  end

  test "tampered packets never unlock", %{key: key} do
    key = %{key | metadata: Map.put(key.metadata, :armor, false)}
    assert {:ok, locked} = GPG.lock("hello", key)
    <<head::binary-size(40), b, rest::binary>> = locked.encrypted
    bad = %{locked | encrypted: head <> <<Bitwise.bxor(b, 0xFF)>> <> rest}
    assert {:error, %ErrorStruct{code: code}} = GPG.unlock(bad, key)
    assert code in ["secrets/authentication_failed", "secrets/invalid_ciphertext", "secrets/wrong_key"]
  end

  test "bad config", %{key: key} do
    bad = %{key | metadata: Map.put(key.metadata, :recipients, ["nope"])}
    assert {:error, %ErrorStruct{code: "secrets/invalid_gpg_config"}} = GPG.lock("x", bad)
    missing = %{key | metadata: Map.put(key.metadata, :homedir, "/nonexistent/dir")}
    assert {:error, %ErrorStruct{code: "secrets/invalid_gpg_config"}} = GPG.lock("x", missing)
    nobin = %{key | metadata: Map.put(key.metadata, :gpg_path, "/nonexistent/gpg")}
    assert {:error, %ErrorStruct{code: "secrets/invalid_gpg_config"}} = GPG.lock("x", nobin)
  end

  test "non-gpg key is secrets/invalid_key" do
    {pub, priv} = :crypto.generate_key(:eddsa, :ed25519)
    assert {:error, %ErrorStruct{code: "secrets/invalid_key"}} =
             GPG.lock("x", %Key{algorithm: :ed25519, public: pub, private: priv})
  end

  test "hung gpg is secrets/gpg_error after the timeout", %{key: key, home: home} do
    stub = Path.join(home, "slow-gpg")
    File.write!(stub, "#!/bin/sh\nsleep 5\n")
    File.chmod!(stub, 0o700)
    key = %{key | metadata: Map.merge(key.metadata, %{gpg_path: stub, timeout_ms: 200})}
    assert {:error, %ErrorStruct{code: "secrets/gpg_error"}} = GPG.lock("x", key)
    refute Enum.any?(File.ls!(System.tmp_dir!()), &String.starts_with?(&1, "comn_gpg_status_"))
  end
end
```

Note the test introduces `metadata.timeout_ms` (default 30_000) so the timeout path is testable; the status tmp dir is named `comn_gpg_status_<unique>`. Both are plan decisions, add them to the spec's config list when documenting (Task 8).

`secrets/gpg_unavailable` is for the no-binary-on-PATH case (`find_executable` nil); an explicit `gpg_path` that does not exist is config error. Test the former only if `gpg` can be hidden from PATH; otherwise leave it to the code path and the moduledoc.

- [ ] **Step 2: Run to verify it fails**

Run: `mix test test/comn/secrets/gpg_test.exs`
Expected: FAIL, `Comn.Secrets.GPG` undefined.

- [ ] **Step 3: Implement `lib/comn/secrets/gpg.ex`**

`@behaviour Comn`, `@behaviour Comn.Secrets`, `alias Comn.Errors.Registry, as: ErrReg`, `alias Comn.Secrets.{Key, LockedBlob, Utils}`. `lock/2` and `unlock/2` for recipient mode only; `wrap`/`unwrap`, Comn callbacks, `put`/`fetch` come in later tasks (leave `wrap`/`unwrap` delegating to `Utils` now, they are one line each, so the behaviour compiles without warnings). Unlock args: `common_args ++ ["--decrypt"]`, stdin is `locked.encrypted`. Validate `homedir` with `File.dir?/1` and `gpg_path` with `File.regular?/1` plus `Path.type/1 == :absolute`. On timeout: `Port.close/1`, return `secrets/gpg_error`. Never log stdin; `Logger.warning` at most the status keywords.

- [ ] **Step 4: Run to verify it passes**

Run: `mix test test/comn/secrets/gpg_test.exs && mix credo --strict && mix compile --warnings-as-errors`
Expected: PASS, clean.

- [ ] **Step 5: Commit**

```bash
git add lib/comn/secrets/gpg.ex test/comn/secrets/gpg_test.exs
git commit -m "feat(secrets): Comn.Secrets.GPG recipient encryption via the gpg binary"
```

---

### Task 4: Symmetric mode

**Files:**
- Modify: `lib/comn/secrets/gpg.ex`
- Test: `test/comn/secrets/gpg_test.exs`

**Interfaces:**
- Consumes: Task 3 `run/3`, `common_args/1`.
- Produces: private `symmetric_args(key)` = `["--pinentry-mode", "loopback", "--passphrase-fd", "0"] ++ armor ++ ["--symmetric"]`; stdin is `key.private <> "\n" <> plaintext`. Unlock in symmetric mode: `["--pinentry-mode", "loopback", "--passphrase-fd", "0", "--decrypt"]`, stdin `key.private <> "\n" <> locked.encrypted`. `metadata.mode == :symmetric`.

- [ ] **Step 1: Write the failing tests**

```elixir
describe "symmetric mode" do
  test "round trip, armored, and gpg -d interop", %{home: home} do
    key = symmetric_key("correct horse", %{homedir: home})
    assert {:ok, %LockedBlob{metadata: %{mode: :symmetric}} = locked} = GPG.lock("hello\nworld", key)
    assert {:ok, "hello\nworld"} = GPG.unlock(locked, key)
    assert locked.key_hint == Key.fingerprint(key)
  end

  test "wrong passphrase is secrets/wrong_key", %{home: home} do
    key = symmetric_key("one", %{homedir: home})
    assert {:ok, locked} = GPG.lock("hello", key)
    assert {:error, %ErrorStruct{code: "secrets/wrong_key"}} =
             GPG.unlock(%{locked | key_hint: nil}, symmetric_key("two", %{homedir: home}))
  end

  test "sign: true is a config error in symmetric mode", %{home: home} do
    key = symmetric_key("pw", %{homedir: home, sign: true})
    assert {:error, %ErrorStruct{code: "secrets/invalid_gpg_config"}} = GPG.lock("x", key)
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `mix test test/comn/secrets/gpg_test.exs --only describe:"symmetric mode"`
Expected: FAIL (symmetric keys take the recipient path and fail on `Base.encode16` of the label or on `INV_RECP`).

- [ ] **Step 3: Implement**

Branch on `key.metadata[:mode] == :symmetric` in `lock/2` and `unlock/2`. The `sign: true` check is part of Task 5's `sign_args/1`; for this task, reject `sign: true` in symmetric mode inside `symmetric_args/1`.

- [ ] **Step 4: Run to verify it passes**

Run: `mix test test/comn/secrets/gpg_test.exs && mix credo --strict`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/comn/secrets/gpg.ex test/comn/secrets/gpg_test.exs
git commit -m "feat(secrets): GPG symmetric mode, passphrase on fd 0"
```

---

### Task 5: Signing and verification

**Files:**
- Modify: `lib/comn/secrets/gpg.ex`
- Test: `test/comn/secrets/gpg_test.exs`

**Interfaces:**
- Consumes: Task 3 `run/3` status lines.
- Produces: private `sign_args(key) :: {:ok, [String.t()], signer_hex | nil} | {:error, ErrorStruct.t()}`: `metadata.sign` absent/false → `[]`; `true` in recipient mode → `["--sign", "--local-user", hex(key.public)]`; `true` in symmetric → `secrets/invalid_gpg_config`; a binary → `gpg_fingerprint_hex` then `["--sign", "--local-user", hex]`. `metadata.signed` on the blob is `signer != nil`. Private `verify_signature(status, expected_hex | nil, required? :: boolean) :: :ok | {:error, ErrorStruct.t()}`: `BADSIG`/`ERRSIG`/`NO_PUBKEY` present → `authentication_failed`; `required?` and no `VALIDSIG` whose last field (primary fingerprint) equals `expected_hex` → `authentication_failed`; else `:ok`. `required?` is `key.metadata[:sign]` truthy or `locked.metadata[:signed] == true`; `expected_hex` is `key.metadata.sign` when it is a binary, else `hex(key.public)` in recipient mode, else nil (symmetric with `signed: true` and no `sign` fingerprint: any `VALIDSIG` passes).

- [ ] **Step 1: Write the failing tests**

```elixir
describe "signing" do
  test "signed round trip", %{key: key} do
    key = %{key | metadata: Map.put(key.metadata, :sign, true)}
    assert {:ok, %LockedBlob{metadata: %{signed: true}} = locked} = GPG.lock("hello", key)
    assert {:ok, "hello"} = GPG.unlock(locked, key)
  end

  test "signature by another key is rejected", %{key: key, home: home} do
    fpr2 = gen_key!(home, "Second <two@comn.invalid>")
    signer2 = %{key | metadata: Map.put(key.metadata, :sign, fpr2)}
    assert {:ok, locked} = GPG.lock("hello", signer2)
    demanding = %{key | metadata: Map.put(key.metadata, :sign, true)}
    assert {:error, %ErrorStruct{code: "secrets/authentication_failed"}} = GPG.unlock(locked, demanding)
    assert {:ok, "hello"} = GPG.unlock(locked, signer2)
  end

  test "unsigned blob with sign demanded is rejected", %{key: key} do
    assert {:ok, locked} = GPG.lock("hello", key)
    demanding = %{key | metadata: Map.put(key.metadata, :sign, true)}
    assert {:error, %ErrorStruct{code: "secrets/authentication_failed"}} = GPG.unlock(locked, demanding)
  end

  test "symmetric blob signed with an explicit fingerprint", %{home: home, fpr: fpr} do
    key = symmetric_key("pw", %{homedir: home, sign: fpr})
    assert {:ok, %LockedBlob{metadata: %{signed: true}} = locked} = GPG.lock("hello", key)
    assert {:ok, "hello"} = GPG.unlock(locked, key)
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `mix test test/comn/secrets/gpg_test.exs --only describe:signing`
Expected: FAIL (`signed` is false; no verification).

- [ ] **Step 3: Implement** per the Interfaces block. Verification runs on the status lines returned by `run/3` after a successful decrypt.

- [ ] **Step 4: Run to verify it passes**

Run: `mix test test/comn/secrets/gpg_test.exs && mix credo --strict`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/comn/secrets/gpg.ex test/comn/secrets/gpg_test.exs
git commit -m "feat(secrets): GPG signing on lock, VALIDSIG policy on unlock"
```

---

### Task 6: wrap/unwrap, Comn introspection, Secrets registry

**Files:**
- Modify: `lib/comn/secrets/gpg.ex` (Comn callbacks)
- Modify: `lib/comn/secrets.ex` (`recon/0` implementations and algorithms, `choices/0` backends and algorithms, moduledoc key-validation bullet and implementations list)
- Test: `test/comn/secrets/gpg_test.exs`, doctest in `gpg.ex` for `look/0` and `recon/0` like `Vault`

**Interfaces:**
- Produces: `look/0`, `recon/0`, `choices/0`, `act/1` exactly as in the spec's Introspection section, with `config` also listing `"gpg_path"` and `"timeout_ms"`. `act/1` clauses: `:lock`, `:unlock`, `:wrap`, `:unwrap` (same shapes as `Local`), `%{action: :put, locked:, repo:, handle:, opts:}`, `%{action: :fetch, repo:, handle:, opts:}` (these two call Task 7's functions; add the clauses in Task 7).

- [ ] **Step 1: Write the failing tests**

```elixir
describe "wrap/unwrap and introspection" do
  test "container round trip", %{key: key} do
    {:ok, a} = GPG.lock("a", key)
    {:ok, b} = GPG.lock("b", key)
    assert {:ok, container} = GPG.wrap([a, b], key)
    assert {:ok, [^a, ^b]} = GPG.unwrap(container, key)
  end

  test "registry lists GPG" do
    assert Comn.Secrets.GPG in Comn.Secrets.recon().implementations
    assert :gpg in Comn.Secrets.recon().algorithms
    assert "GPG" in Comn.Secrets.choices().backends
    assert %{backend: :gpg, modes: [:recipient, :symmetric], signing: true} = GPG.recon()
    assert {:error, %ErrorStruct{}} = GPG.act(%{action: :nope})
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `mix test test/comn/secrets/gpg_test.exs --only describe:"wrap/unwrap and introspection"`
Expected: FAIL on the registry assertions.

- [ ] **Step 3: Implement** the Comn callbacks and the `secrets.ex` edits. Add the `look`/`recon` doctests and ensure `doctest Comn.Secrets.GPG` is picked up by whatever file doctests `Vault` (grep `doctest Comn.Secrets.Vault`; mirror it).

- [ ] **Step 4: Run the whole secrets suite**

Run: `mix test test/comn/secrets/ && mix credo --strict`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/comn/secrets/gpg.ex lib/comn/secrets.ex test/comn/secrets/gpg_test.exs
git commit -m "feat(secrets): GPG wrap/unwrap and Comn introspection"
```

---

### Task 7: `put/4` and `fetch/3` to Repo shapes

**Files:**
- Modify: `lib/comn/secrets/gpg.ex`
- Test: `test/comn/secrets/gpg_test.exs`

**Interfaces:**
- Consumes: `Comn.Repo.File.open/2`, `load/1`, `read/1`, `set/2`, `get/2`; `Comn.Repo.Table.open/2`, `set/2`, `get/2`; `Comn.Events.EventStruct.new/1` (mints `id`); `Comn.Repo.Handle` with `shape` field.
- Produces:
  - `put(LockedBlob.t(), repo :: module(), handle :: Comn.Repo.Handle.t(), opts :: keyword()) :: {:ok, Comn.Repo.Handle.t()} | {:ok, event_id :: String.t(), set_result :: term()} | {:error, ErrorStruct.t()}`. `as: :raw` → `repo == Comn.Repo.File` or `secrets/invalid_gpg_config`; calls `repo.set(handle, value: locked.encrypted)` and returns its `{:ok, handle}`. Default → `e = EventStruct.new(type: :secrets_locked, topic: "comn.secrets", data: locked)`; `repo.set(handle, event: e)`; on `:ok` or `{:ok, _}` returns `{:ok, e.id, result}`; an `{:error, _}` passes through.
  - `fetch(repo :: module(), handle :: Comn.Repo.Handle.t(), opts :: keyword()) :: {:ok, LockedBlob.t()} | {:error, ErrorStruct.t()}`. `as: :raw` → `Comn.Repo.File.read(handle)` and rebuild `%LockedBlob{cipher: :gpg, encrypted: bytes, metadata: %{armor: String.starts_with?(bytes, "-----BEGIN PGP MESSAGE-----"), mode: nil, signed: nil}}`. `id: id` → `repo.get(handle, id: id)`; the event's `data` must be a `%LockedBlob{cipher: :gpg}` else `secrets/invalid_container`. Neither option → `secrets/invalid_gpg_config`.
  - `act/1` clauses for `:put` and `:fetch`.

- [ ] **Step 1: Write the failing tests**

```elixir
describe "repo destinations" do
  setup %{home: home} do
    root = Path.join(home, "repo")
    File.mkdir_p!(root)
    {:ok, root: root}
  end

  test "raw file: gpg -d reads it, raw fetch unlocks", %{key: key, home: home, root: root} do
    {:ok, locked} = GPG.lock("hello", key)
    {:ok, f} = Comn.Repo.File.open("secret.asc", root: root, mode: [:write, :binary])
    {:ok, f} = Comn.Repo.File.load(f)
    assert {:ok, %Comn.Repo.Handle{}} = GPG.put(locked, Comn.Repo.File, f, as: :raw)
    :ok = Comn.Repo.File.close(f)
    assert shell_decrypt!(home, File.read!(Path.join(root, "secret.asc"))) == "hello"

    {:ok, f} = Comn.Repo.File.open("secret.asc", root: root)
    {:ok, f} = Comn.Repo.File.load(f)
    assert {:ok, %LockedBlob{cipher: :gpg, key_hint: nil, metadata: %{armor: true}} = fetched} =
             GPG.fetch(Comn.Repo.File, f, as: :raw)
    assert {:ok, "hello"} = GPG.unlock(fetched, key)
  end

  test "raw fetch of binary output is not armored", %{key: key, root: root} do
    key = %{key | metadata: Map.put(key.metadata, :armor, false)}
    {:ok, locked} = GPG.lock("hello", key)
    {:ok, f} = Comn.Repo.File.open("secret.gpg", root: root, mode: [:write, :binary])
    {:ok, f} = Comn.Repo.File.load(f)
    {:ok, _} = GPG.put(locked, Comn.Repo.File, f, as: :raw)
    :ok = Comn.Repo.File.close(f)
    {:ok, f} = Comn.Repo.File.open("secret.gpg", root: root)
    {:ok, f} = Comn.Repo.File.load(f)
    assert {:ok, %LockedBlob{metadata: %{armor: false}} = fetched} = GPG.fetch(Comn.Repo.File, f, as: :raw)
    assert {:ok, "hello"} = GPG.unlock(fetched, key)
  end

  test "event form into a Table", %{key: key} do
    {:ok, t} = Comn.Repo.Table.open(:"gpg_#{System.unique_integer([:positive])}")
    {:ok, locked} = GPG.lock("hello", key)
    assert {:ok, id, :ok} = GPG.put(locked, Comn.Repo.Table, t, [])
    assert {:ok, ^locked} = GPG.fetch(Comn.Repo.Table, t, id: id)
    Comn.Repo.Table.drop(t)
  end

  test "event form into a File log", %{key: key, root: root} do
    {:ok, locked} = GPG.lock("hello", key)
    {:ok, f} = Comn.Repo.File.open("log.events", root: root, mode: [:append, :binary])
    {:ok, f} = Comn.Repo.File.load(f)
    assert {:ok, id, {:ok, f}} = GPG.put(locked, Comn.Repo.File, f, [])
    assert {:ok, ^locked} = GPG.fetch(Comn.Repo.File, f, id: id)
    Comn.Repo.File.close(f)
  end

  test "raw on a non-File shape is a config error", %{key: key} do
    {:ok, t} = Comn.Repo.Table.open(:"gpg_raw_#{System.unique_integer([:positive])}")
    {:ok, locked} = GPG.lock("hello", key)
    assert {:error, %ErrorStruct{code: "secrets/invalid_gpg_config"}} = GPG.put(locked, Comn.Repo.Table, t, as: :raw)
    Comn.Repo.Table.drop(t)
  end
end
```

The File `open` modes and whether `load` is needed before `set(value:)`/`set(event:)` must be checked against `lib/comn/repo/file/local.ex` (`set` requires `:loaded`; `load` on a write-mode file of a non-existent path may need the file to exist first). Adjust the test setup, not the semantics.

- [ ] **Step 2: Run to verify it fails**

Run: `mix test test/comn/secrets/gpg_test.exs --only describe:"repo destinations"`
Expected: FAIL, `put/4` undefined.

- [ ] **Step 3: Implement** `put/4`, `fetch/3`, and the two `act/1` clauses.

- [ ] **Step 4: Run the full suite**

Run: `mix test && mix credo --strict && mix compile --warnings-as-errors`
Expected: PASS, clean.

- [ ] **Step 5: Commit**

```bash
git add lib/comn/secrets/gpg.ex test/comn/secrets/gpg_test.exs
git commit -m "feat(secrets): GPG put/fetch to any Comn.Repo shape"
```

---

### Task 8: Docs and analyzers

**Files:**
- Modify: `README.md` (status table row at line 21; Secrets section after the Vault example; file layout list near line 571)
- Modify: `CHANGELOG.md` (new `## Unreleased` section above `0.7.0`)
- Modify: `lib/comn/secrets/gpg.ex` moduledoc (config keys incl. `gpg_path`, `timeout_ms`; the two key shapes; the signing policy; the process-boundary note that only the byte count is on argv)
- Modify: `docs/superpowers/specs/2026-11-03-secrets-gpg-design.md` (add `timeout_ms` and the status tmp dir name to the config list, status `Draft` → `Implemented`)
- Modify: `mix.exs` ex_doc groups if `Comn.Secrets.Vault` is listed in a group (grep `Secrets.Vault` in `mix.exs`); add `Comn.Secrets.GPG` beside it.

- [ ] **Step 1: Write the docs.** README example:

```elixir
alias Comn.Secrets.{GPG, Key}

key = %Key{
  algorithm: :gpg,
  public: Base.decode16!("<40 or 64 hex primary fingerprint>"),
  metadata: %{homedir: "/home/me/.gnupg", sign: true}
}

{:ok, locked} = GPG.lock("sensitive data", key)     # locked.encrypted is an armored PGP message
{:ok, "sensitive data"} = GPG.unlock(locked, key)   # VALIDSIG checked

{:ok, f} = Comn.Repo.File.open("secret.asc", root: "/srv/secrets", mode: [:write, :binary])
{:ok, f} = Comn.Repo.File.load(f)
{:ok, _f} = GPG.put(locked, Comn.Repo.File, f, as: :raw)   # gpg -d secret.asc works
```

and a symmetric example with `private: passphrase, metadata: %{mode: :symmetric}`. Markdown must be lint-clean (language tags, blank lines around fences and lists).

- [ ] **Step 2: Run every analyzer**

Run: `mix compile --warnings-as-errors && mix credo --strict && mix test && mix vet && mix deps.audit && mix sobelow --exit`
Expected: all clean. If sobelow or Credo flags the port spawn or `File.chmod`, fix the code (for example, validate `gpg_path` before `Port.open`); no skip comments.

- [ ] **Step 3: Run `mix docs`**

Run: `mix docs 2>&1 | tail -5`
Expected: no warnings about `Comn.Secrets.GPG`.

- [ ] **Step 4: Commit**

```bash
git add README.md CHANGELOG.md lib/comn/secrets/gpg.ex docs/superpowers/specs/2026-11-03-secrets-gpg-design.md mix.exs
git commit -m "docs(secrets): Comn.Secrets.GPG README, moduledoc, changelog"
```
