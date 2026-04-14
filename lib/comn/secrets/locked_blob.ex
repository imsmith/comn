defmodule Comn.Secrets.LockedBlob do
  @moduledoc """
  Encrypted data blob.

  A LockedBlob is the result of calling `lock/2` on a binary blob, or `wrap/2`
  on a collection of blobs. It can contain:
  - A single encrypted secret (from `lock/2`)
  - An encrypted container of multiple secrets (from `wrap/2`)

  The structure is identical in both cases - the `encrypted` field contains
  either the ciphertext of a single blob or the ciphertext of a serialized
  Container struct.

  ## Fields

  - `cipher` - The encryption algorithm used (:aes_gcm, :chacha20_poly1305)
  - `encrypted` - The encrypted binary data (single blob or serialized container)
  - `tag` - AEAD authentication tag (for verifying ciphertext and metadata integrity)
  - `key_hint` - Self-describing key fingerprint (17 bytes: 1-byte algorithm + 16-byte BLAKE2b hash)
  - `nonce` - Nonce/IV used for encryption
  - `metadata` - Arbitrary metadata about the blob (authenticated via AEAD associated data)

  ## Key Hint Format

  The `key_hint` is a deterministic fingerprint generated from the public key:
  - Byte 0: Algorithm identifier (0x01=Ed25519, 0x02=RSA-4096, 0x03=ECDSA-P256)
  - Bytes 1-16: BLAKE2b hash of public key (truncated to 128 bits)

  This provides fast key lookup without revealing key ownership or metadata.

  ## AEAD Authentication

  Both AES-GCM and ChaCha20-Poly1305 are AEAD ciphers. The `tag` field contains
  the authentication tag that verifies both the ciphertext and the metadata.
  Implementations should include serialized metadata as associated data during
  encryption/decryption.

  ## Container Security

  When a LockedBlob contains an encrypted container (from `wrap/2`), the
  authentication tag protects the entire collection structure:
  - Number of blobs in the container
  - Order of blobs
  - Container metadata
  - Each blob's ciphertext

  Any modification to the container (reordering, deletion, injection, metadata
  tampering) will cause tag verification to fail during `unwrap/2`.

  This is critical: even though individual blobs are already encrypted, the
  container MUST be encrypted again to prevent structure manipulation attacks.
  """

  @type cipher :: :aes_gcm | :chacha20_poly1305

  @type t :: %__MODULE__{
          cipher: cipher(),
          encrypted: binary(),
          tag: binary() | nil,
          key_hint: binary() | nil,
          nonce: binary() | nil,
          metadata: map()
        }

  @enforce_keys [:cipher, :encrypted]
  defstruct [
    :cipher,
    :encrypted,
    :tag,
    :key_hint,
    :nonce,
    metadata: %{}
  ]
end
