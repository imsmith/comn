defmodule Comn.Secrets.Key do
  @moduledoc """
  Cryptographic key pair for locking/unlocking secrets.

  A Key represents either a symmetric or asymmetric cryptographic key
  used for encryption and decryption operations.

  ## Fields

  - `id` - Key identifier/fingerprint
  - `algorithm` - Key algorithm (:ed25519, :rsa_4096, :ecdsa_p256)
  - `public` - Public key material
  - `private` - Private key material (may be nil for public-only keys)
  - `metadata` - Arbitrary metadata about the key

  ## Key Sources

  Keys can be loaded from various sources:

  - Files (PEM format)
  - Environment variables
  - Context IDs
  - Generated on-demand

  ## Fingerprints

  Key fingerprints are self-describing 17-byte identifiers:
  - 1 byte: algorithm type (0x01=Ed25519, 0x02=RSA-4096, 0x03=ECDSA-P256)
  - 16 bytes: BLAKE2b hash of public key (truncated to 128 bits)

  This provides cryptographic identification without leaking key metadata.

  ## Example

      # Generate a new key
      key = Key.generate(:ed25519)

      # Load from file
      key = Key.from_file("~/.keys/work.pem")

      # Load from environment
      key = Key.from_env("SECRET_KEY")

      # Get fingerprint for key_hint
      hint = Key.fingerprint(key)
  """

  @type algorithm :: :ed25519 | :rsa_4096 | :ecdsa_p256

  @type t :: %__MODULE__{
          id: binary(),
          algorithm: algorithm(),
          public: binary(),
          private: binary() | nil,
          metadata: map()
        }

  @enforce_keys [:algorithm, :public]
  defstruct [
    :id,
    :algorithm,
    :public,
    :private,
    metadata: %{}
  ]

  # Algorithm type bytes for fingerprints
  @algorithm_bytes %{
    ed25519: 0x01,
    rsa_4096: 0x02,
    ecdsa_p256: 0x03
  }

  @doc """
  Generate a deterministic fingerprint for a key.

  Returns a 17-byte binary: 1 byte algorithm identifier + 16 bytes BLAKE2b hash.

  ## Example

      key = %Key{algorithm: :ed25519, public: <<...>>}
      hint = Key.fingerprint(key)
      # => <<0x01, ...16 bytes of hash...>>
  """
  @spec fingerprint(t()) :: binary()
  def fingerprint(%__MODULE__{algorithm: algorithm, public: public}) do
    algorithm_byte = Map.fetch!(@algorithm_bytes, algorithm)
    hash = :crypto.hash(:blake2b, public) |> binary_part(0, 16)
    <<algorithm_byte, hash::binary>>
  end

  @doc """
  Extract the algorithm from a key fingerprint.

  ## Example

      algorithm = Key.algorithm_from_fingerprint(<<0x01, rest::binary>>)
      # => :ed25519
  """
  @spec algorithm_from_fingerprint(binary()) :: algorithm() | :unknown
  def algorithm_from_fingerprint(<<0x01, _rest::binary>>), do: :ed25519
  def algorithm_from_fingerprint(<<0x02, _rest::binary>>), do: :rsa_4096
  def algorithm_from_fingerprint(<<0x03, _rest::binary>>), do: :ecdsa_p256
  def algorithm_from_fingerprint(_), do: :unknown

  @doc """
  Verify if a fingerprint matches a key.

  ## Example

      if Key.fingerprint_matches?(hint, key) do
        # Proceed with decryption
      end
  """
  @spec fingerprint_matches?(binary(), t()) :: boolean()
  def fingerprint_matches?(fingerprint, %__MODULE__{} = key) do
    fingerprint == fingerprint(key)
  end
end
