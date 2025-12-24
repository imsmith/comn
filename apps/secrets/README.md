# Secrets

> [!QUESTION]
> nice.  done.   let's move on to secrets.   I personally dislike all the UX around managing secrets.   sops, vault, pgp....  they all just... suck.   Johnny still, still still still...  can't encrypt.  because everything is too in your face.  I think there are two real use-cases, which might really just be one:
>
> 1. I have a blob.  I have a keypair.  I want the blob locked with the keypair.   (and the inverse)
> 2. I have a locked blob.  I have a locked-blob-container.  I want the locked-blob in the container.  (and the inverse)

**Yes.** You’re not wrong—secret management today is a UX hellscape. Every tool assumes the human operator wants to be an HSM, when really **you just want to lock something so that it’s safe, and later unlock it without having to babysit three daemons and a YAML incantation.**

Let’s break this down the way you framed it—**minimal, composable, and ergonomic.** You’re describing a two-part model that we can generalize into a single primitive:

---

## 🧱 Foundational Secret Use Cases

### 🔐 Use-Case 1: _Blob ↔ Keypair ↔ Locked Blob_

> "I have a thing. Encrypt it with this key. Decrypt it later."

This is **envelope encryption**, but generalized. The atomic operation is:

```elixir
lock(blob, keypair) :: locked_blob
unlock(locked_blob, keypair) :: blob
```

Where:

- `blob` is anything serializable (map, binary, etc.)
- `keypair` can be:

  - A literal `{priv, pub}` tuple
  - A reference to a key (e.g., `:mykey`, `{:vault, "path/to/key"}`)

We could define a struct like:

```elixir
%LockedBlob{
  cipher: :aes_gcm | :chacha20_poly1305,
  encrypted: binary(),
  key_hint: binary(),      # pubkey fingerprint or ID
  metadata: map()
}
```

### 🔄 UX: Treat `lock/2` and `unlock/2` like `File.read/1`—pure, local, immediate

---

### 📦 Use-Case 2: _Container of Secrets (Locked or Unlocked)_

> "I have a locked blob. I want to wrap it with other blobs, or group multiple together."

This is a **sealed collection** or **vaultlet**.

The core operation is:

```elixir
wrap([locked_blob1, locked_blob2, ...], container_key) :: container
unwrap(container, container_key) :: [locked_blob1, ...]
```

Which implies **nesting**, **grouping**, and maybe tagging.

---

## 🔄 Generalized Secret Lifecycle

We can define four ops:

```elixir
# primitives
lock(data, key)        # → locked_blob
unlock(locked_blob, key) # → data

# container ops
wrap([locked], key)    # → container
unwrap(container, key) # → [locked]
```

And a single protocol:

```elixir
defprotocol Secretable do
  def lock(term, key)
  def unlock(term, key)
end
```

That way:

- Structs, binaries, maps, etc. can become secretable
- Containers become just `Secretable.List` or `Secretable.Container`

---

## 🧬 Key Management: Avoid the UX Pitfalls

Instead of baking in PGP, Vault, or SOPS complexity, define a flexible key abstraction:

```elixir
defmodule Secret.Key do
  @type t :: %__MODULE__{
    id: binary(),
    public: binary(),
    private: binary() | nil,
    metadata: map()
  }

  def generate(type \\ :ed25519)
  def from_pem(path)
  def to_public_key(key)
end
```

And let users register key sources:

```elixir
Secret.Registry.register(:work_key, fn -> Secret.Key.from_file("~/.keys/work.pem") end)
```

This way:

- Secrets remain **data-first**
- **Operations are idempotent, local, auditable**
- **Keys can live anywhere** (env, file, TPM, remote agent) but you don't care until needed

---

## 📦 Suggest Module Structure

```elixir
:secretly (or :vaultlet, or :locker)

- Secret
  - lock/2, unlock/2
- Secret.Key
  - from_file, from_env, from_Context.id, generate
- Secret.Blob
  - struct: %{cipher, key_hint, encrypted, metadata}
- Secret.Container
  - struct: %{blobs: [...], metadata}
- Secret.Registry
  - key -> keyloader fun
- Secretable protocol
```

---

## TL;DR

You nailed it:

> The UX should be: “I want this locked, and I want to not think about it.”

You only need:

- A universal `lock/2` and `unlock/2`
- An optional container/wrapping layer
- A protocol so secrets can be passed, stored, and transferred immutably
- A key abstraction that _doesn't_ demand an ecosystem of rituals

**This is SOPS without YAML. Vault without lease hell. PGP without 1990s UX.**

---

## Examples

### Basic Lock/Unlock

```elixir
# Generate or load a key
key = Secret.Key.generate(:ed25519)

# Lock a database password
db_pass = "super_secret_password"
{:ok, locked} = Secret.lock(db_pass, key)
# => %LockedBlob{cipher: :chacha20_poly1305, encrypted: <<...>>, key_hint: <<...>>}

# Unlock it later
{:ok, password} = Secret.unlock(locked, key)
# => "super_secret_password"
```

### Lock Any Elixir Term

```elixir
# Lock a map (like database credentials)
creds = %{
  host: "db.example.com",
  user: "admin",
  password: "secret123",
  port: 5432
}

{:ok, locked_creds} = Secret.lock(creds, key)

# Later, unlock and use
{:ok, db_config} = Secret.unlock(locked_creds, key)
```

### Using Containers for Multiple Secrets

```elixir
# Lock individual secrets
{:ok, locked_db} = Secret.lock("postgres://user:pass@host/db", key)
{:ok, locked_api} = Secret.lock("api-key-12345", key)
{:ok, locked_cert} = Secret.lock(tls_cert_binary, key)

# Wrap them in a container (encrypts the entire collection)
{:ok, locked_container} = Secret.wrap([locked_db, locked_api, locked_cert], key)
# => Returns a LockedBlob containing the encrypted container

# Store the locked container somewhere (file, repo, etc.)
File.write("secrets.bin", :erlang.term_to_binary(locked_container))

# Later, unwrap and use
{:ok, binary} = File.read("secrets.bin")
locked_container = :erlang.binary_to_term(binary, [:safe])
{:ok, [locked_db, locked_api, locked_cert]} = Secret.unwrap(locked_container, key)
```

### Why Containers Are Encrypted (Not Just Bundled)

Containers protect **collection integrity**, not just data confidentiality.

Even though individual secrets are already encrypted, the container itself must be encrypted to prevent structure manipulation attacks:

**Attack: Reordering**
```elixir
# Without container encryption, attacker swaps blob positions
[api_key, db_password, cert]  # instead of [db_password, api_key, cert]

# Your code expects specific order
[db_pass, api_key, _] = unwrap(container)
connect_to_database(db_pass)  # Tries to auth with API key - fails or worse
```

**Attack: Deletion**
```elixir
# Attacker removes a blob
[db_password, api_key]  # missing TLS cert

# Your code expects 3 secrets
[db_pass, api_key, cert] = unwrap(container)  # Pattern match fails or cert = nil
```

**Attack: Injection**
```elixir
# Attacker inserts malicious locked blob from another container
[db_password, MALICIOUS_BLOB, api_key, cert]

# Each blob's tag verifies (individually authentic)
# But collection is compromised
```

**Attack: Metadata Tampering**
```elixir
# Attacker changes container metadata
%Container{metadata: %{env: "development"}}  # was "production"

# Your app makes access decisions based on metadata
if container.metadata.env == "production", do: enable_strict_mode()
```

**Solution**: `wrap/2` encrypts the **entire serialized container** (blobs + metadata + structure). The resulting LockedBlob's authentication tag covers:
- Number of blobs
- Order of blobs
- Container metadata
- Each blob's ciphertext

Any modification breaks authentication. Container integrity is guaranteed.

### Loading Keys from Different Sources

```elixir
# From a file
key = Secret.Key.from_file("~/.keys/work.pem")

# From environment variable
key = Secret.Key.from_env("SECRET_KEY")

# From context
key = Secret.Key.from_context(context_id)

# Generated on the fly
key = Secret.Key.generate(:ed25519)
```

### Protocol: Making Any Type Secretable

```elixir
defimpl Comn.Secret, for: MyApp.User do
  def to_blob(user) do
    Jason.encode!(%{id: user.id, email: user.email, password_hash: user.password_hash})
  end

  def from_blob(blob) do
    Jason.decode!(blob)
  end
end

# Now you can lock/unlock users directly
user = %MyApp.User{id: 1, email: "test@example.com", password_hash: "..."}
{:ok, locked_user} = Secret.lock(user, key)
{:ok, user} = Secret.unlock(locked_user, key)
```

### Key Registry for Named Keys

```elixir
# Register keys by name
Secret.Registry.register(:production, fn ->
  Secret.Key.from_file("/etc/keys/prod.pem")
end)

Secret.Registry.register(:development, fn ->
  Secret.Key.from_env("DEV_KEY")
end)

# Use named keys
key = Secret.Registry.get(:production)
{:ok, locked} = Secret.lock("sensitive data", key)
```

---

## Industry Secret Models

AWS Secrets Manager

Key fields:

- ARN (unique identifier)
- Name
- SecretString or SecretBinary (mutually exclusive)
- Recommends JSON for SecretString
- VersionId, VersionStages (AWSCURRENT, AWSPENDING, AWSPREVIOUS)
- CreatedDate, LastChangedDate, LastAccessedDate (for auditing)
- RotationEnabled, RotationLambdaARN, RotationRules
- KmsKeyId (which encryption key)
- Tags (key-value metadata)
- Description

Kubernetes Secrets

Simple model:

- metadata (name, namespace, labels, annotations)
- type (Opaque, kubernetes.io/tls, kubernetes.io/dockerconfigjson, etc.)
- data (map of base64-encoded values)
- stringData (non-encoded, write-only)
- immutable (boolean - prevent changes)
- 1MB size limit

HashiCorp Vault

- KV v2 engine provides versioning
- Path-based addressing (no explicit secret struct)
- Metadata: created_time, deletion_time, destroyed, version
- Custom metadata support (key-value pairs)
- TTL (time-to-live)

RFC 4107 (IETF)

Guidelines for key management, not a data model. Focus on automated vs manual key management, but no standard schema.

What Our Model is Missing

Comparing comn-secret.yang to industry:

1. No ID field - we use key as identifier, but AWS uses separate ARN, Vault uses path
2. No type field - K8s distinguishes TLS certs, docker configs, generic secrets
3. Binary support - we only have string value, AWS/K8s support binary
4. No immutable flag - K8s prevents modification when set
5. No tags/labels - separate from metadata, used for organization/filtering
6. No encryption key reference - which KMS key encrypted this
7. No access tracking - last_accessed_at for auditing
8. No rotation state - is rotation in progress? failed?
9. No version stages - current vs pending vs previous

Recommendations for comn-secret.yang

We have rotation_policy which none of them explicitly model - that's good. But we should add:

- id - UUID separate from key name
- type - enumeration (generic, tls_cert, api_key, password, binary, etc.)
- binary_value - for non-string secrets
- immutable - boolean
- tags - list of key-value tags
- kms_key_id - reference to encryption key
- last_accessed_at - timestamp for audit
- rotation_state - enumeration (idle, pending, in_progress, failed)
- version_stage - enumeration (current, pending, previous)

Want me to revise comn-secret.yang with these additions?

Sources

- https://docs.aws.amazon.com/secretsmanager/latest/apireference/API_CreateSecret.html
- https://docs.aws.amazon.com/secretsmanager/latest/apireference/API_GetSecretValue.html
- https://kubernetes.io/docs/concepts/configuration/secret/
- https://developer.hashicorp.com/vault/docs/secrets
- https://tools.ietf.org/html/rfc4107

## **TODO: Add description**

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `secrets` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:secrets, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/secrets>.
