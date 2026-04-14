defmodule Comn.Secrets do
  @moduledoc """
  Behaviour for secret locking/unlocking implementations.

  Also implements `@behaviour Comn` for uniform introspection.

  Secrets are encrypted blobs with a simple interface:
  - `lock/2` - Encrypt a blob with a key
  - `unlock/2` - Decrypt a locked blob with a key
  - `wrap/2` - Bundle multiple locked blobs into a container
  - `unwrap/2` - Extract locked blobs from a container

  ## Philosophy

  Secrets are just encrypted data. No rotation schedules, no version stages,
  no lifecycle management. If you want rotation, call lock/2 again. If you
  want versioning, store multiple blobs.

  ## Implementation Requirements

  Implementations MUST:

  1. **Validate keys** - Verify key structure matches algorithm before use:
     - Ed25519: 32-byte private key, 32-byte public key
     - RSA-4096: 4096-bit modulus
     - ECDSA-P256: Valid P-256 curve points
     Return `{:error, :invalid_key}` for malformed keys.

  2. **Use unique nonces** - Never reuse nonces with the same key.
     For AEAD ciphers, nonce reuse is catastrophic.

  3. **Verify authentication tags** - Always check AEAD tags before returning
     decrypted data. Tag mismatch = `{:error, :authentication_failed}`.

  4. **Handle errors safely** - Never include plaintext or keys in error messages.

  ## Example Implementation

      defmodule MyApp.Secrets.Local do
        @behaviour Comn.Secrets

        alias Comn.Secrets.{LockedBlob, Container, Key}

        @impl true
        def lock(blob, %Key{} = key) when is_binary(blob) do
          # Use :crypto.crypto_one_time_aead/6 for encryption
          # Return {:ok, %LockedBlob{}}
        end

        @impl true
        def unlock(%LockedBlob{} = locked, %Key{} = key) do
          # Decrypt and return {:ok, blob}
        end

        @impl true
        def wrap(blobs, %Key{} = key) when is_list(blobs) do
          # 1. Create container: %Container{blobs: blobs, metadata: %{...}}
          # 2. Serialize: :erlang.term_to_binary(container, [:safe])
          # 3. Encrypt serialized container (lock operation)
          # Return {:ok, %LockedBlob{}} containing encrypted container
        end

        @impl true
        def unwrap(%LockedBlob{} = locked_container, %Key{} = key) do
          # 1. Decrypt container (unlock operation)
          # 2. Deserialize: :erlang.binary_to_term(binary, [:safe])
          # 3. Extract blobs from container
          # Return {:ok, [%LockedBlob{}, ...]}
        end
      end
  """

  alias Comn.Secrets.{LockedBlob, Key}

  @doc """
  Lock (encrypt) a binary blob with a key.

  Returns `{:ok, locked_blob}` or `{:error, reason}`.
  """
  @callback lock(blob :: binary(), key :: Key.t()) ::
              {:ok, LockedBlob.t()} | {:error, term()}

  @doc """
  Unlock (decrypt) a locked blob with a key.

  Returns `{:ok, binary}` or `{:error, reason}`.
  """
  @callback unlock(locked :: LockedBlob.t(), key :: Key.t()) ::
              {:ok, binary()} | {:error, term()}

  @doc """
  Wrap multiple locked blobs into an encrypted container.

  Wrapping MUST encrypt the entire container structure, not just bundle blobs.
  This protects collection integrity against:
  - Reordering attacks (changing blob order)
  - Deletion attacks (removing blobs)
  - Injection attacks (inserting blobs from other containers)
  - Metadata tampering (changing container metadata)
  - Replay attacks (using old versions of the container)

  ## Implementation

  1. Create Container struct with blobs and metadata
  2. Serialize container to binary (use `:erlang.term_to_binary(container, [:safe])`)
  3. Encrypt serialized container with key (lock operation)
  4. Return LockedBlob containing encrypted container

  The authentication tag in the resulting LockedBlob covers the entire
  container structure (number of blobs, order, metadata, ciphertexts).

  Returns `{:ok, locked_container}` where locked_container is a LockedBlob,
  or `{:error, reason}`.
  """
  @callback wrap(blobs :: [LockedBlob.t()], key :: Key.t()) ::
              {:ok, LockedBlob.t()} | {:error, term()}

  @doc """
  Unwrap an encrypted container to extract locked blobs.

  Unwrapping MUST:
  1. Decrypt the container LockedBlob (unlock operation)
  2. Verify authentication tag (automatic with AEAD, detects tampering)
  3. Deserialize container (use `:erlang.binary_to_term(binary, [:safe])`)
  4. Extract and return the list of blobs

  Tag verification failure means the container structure was modified
  (reordered, deleted, injected, or metadata tampered).

  Returns `{:ok, [locked_blob]}` or `{:error, reason}`.
  Common errors:
  - `:authentication_failed` - Container was modified
  - `:invalid_container` - Deserialization failed
  - `:wrong_key` - Key doesn't match container
  """
  @callback unwrap(locked_container :: LockedBlob.t(), key :: Key.t()) ::
              {:ok, [LockedBlob.t()]} | {:error, term()}

  @behaviour Comn

  @impl Comn
  def look, do: "Secrets — lock/unlock encrypted blobs, wrap/unwrap containers"

  @impl Comn
  def recon do
    %{
      callbacks: [:lock, :unlock, :wrap, :unwrap],
      algorithms: [:ed25519, :rsa_4096, :ecdsa_p256],
      implementations: [Comn.Secrets.Local, Comn.Secrets.Vault],
      type: :behaviour
    }
  end

  @impl Comn
  def choices do
    %{
      backends: ["Local", "Vault"],
      algorithms: ["ed25519", "rsa_4096", "ecdsa_p256"]
    }
  end

  @impl Comn
  def act(_input), do: {:error, :behaviour_only}
end
