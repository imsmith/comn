defmodule Comn.Secrets.Local do
  @moduledoc """
  Local implementation of `Comn.Secrets` using Erlang `:crypto`.

  Uses Ed25519 keys for identity and ChaCha20-Poly1305 for AEAD encryption
  with a unique nonce per operation. Similar to how `age` works — modern
  cryptographic primitives, no lifecycle management overhead.

  ## Examples

      iex> {pub, priv} = :crypto.generate_key(:eddsa, :ed25519)
      iex> key = %Comn.Secrets.Key{
      ...>   id: :crypto.hash(:blake2b, pub) |> binary_part(0, 16),
      ...>   algorithm: :ed25519, public: pub, private: priv
      ...> }
      iex> {:ok, locked} = Comn.Secrets.Local.lock("hello", key)
      iex> {:ok, "hello"} = Comn.Secrets.Local.unlock(locked, key)
  """

  @behaviour Comn
  @behaviour Comn.Secrets

  alias Comn.Errors.Registry, as: ErrReg
  alias Comn.Secrets.{Key, LockedBlob, Utils}

  @impl true
  def lock(blob, %Key{} = key) when is_binary(blob) do
    # Validate key first
    with :ok <- Utils.validate_key(key) do
      # Derive symmetric key from Ed25519 private key
      # In production, you'd use proper key derivation (HKDF)
      # For now, hash the private key to get 32 bytes for ChaCha20
      symmetric_key = :crypto.hash(:sha256, key.private)

      # Generate random nonce (12 bytes for ChaCha20-Poly1305)
      nonce = :crypto.strong_rand_bytes(12)

      # Prepare metadata
      metadata = %{
        created_at: DateTime.utc_now() |> DateTime.to_iso8601(),
        algorithm: key.algorithm
      }

      # Serialize metadata for AAD
      aad = :erlang.term_to_binary(metadata)

      # Encrypt with ChaCha20-Poly1305
      {ciphertext, tag} =
        :crypto.crypto_one_time_aead(
          :chacha20_poly1305,
          symmetric_key,
          nonce,
          blob,
          aad,
          true
        )

      locked = %LockedBlob{
        cipher: :chacha20_poly1305,
        encrypted: ciphertext,
        tag: tag,
        nonce: nonce,
        key_hint: Key.fingerprint(key),
        metadata: metadata
      }

      {:ok, locked}
    end
  end

  def lock(_blob, _key), do: {:error, ErrReg.error!("secrets/invalid_key")}

  @impl true
  def unlock(%LockedBlob{} = locked, %Key{} = key) do
    # Validate key first
    with :ok <- Utils.validate_key(key),
         true <- Key.fingerprint_matches?(locked.key_hint, key) do
      # Derive same symmetric key
      symmetric_key = :crypto.hash(:sha256, key.private)

      # Serialize metadata for AAD
      aad = :erlang.term_to_binary(locked.metadata)

      # Decrypt with tag verification
      case :crypto.crypto_one_time_aead(
             locked.cipher,
             symmetric_key,
             locked.nonce,
             locked.encrypted,
             aad,
             locked.tag,
             false
           ) do
        plaintext when is_binary(plaintext) ->
          {:ok, plaintext}

        :error ->
          {:error, ErrReg.error!("secrets/authentication_failed")}
      end
    else
      false ->
        {:error, ErrReg.error!("secrets/wrong_key")}

      {:error, _} = err ->
        err
    end
  end

  def unlock(_locked, _key), do: {:error, ErrReg.error!("secrets/invalid_key")}

  @impl true
  def wrap(blobs, key), do: Utils.wrap(__MODULE__, blobs, key)

  @impl true
  def unwrap(locked, key), do: Utils.unwrap(__MODULE__, locked, key)

  # Comn callbacks

  @impl Comn
  def look, do: "Secrets.Local — ChaCha20-Poly1305 local encryption with Ed25519 keys"

  @impl Comn
  def recon do
    %{
      backend: :local_crypto,
      cipher: :chacha20_poly1305,
      key_derivation: :sha256,
      type: :implementation
    }
  end

  @impl Comn
  def choices do
    %{operations: ["lock", "unlock", "wrap", "unwrap"]}
  end

  @impl Comn
  def act(%{action: :lock, blob: blob, key: key}), do: lock(blob, key)
  def act(%{action: :unlock, locked: locked, key: key}), do: unlock(locked, key)
  def act(%{action: :wrap, blobs: blobs, key: key}), do: wrap(blobs, key)
  def act(%{action: :unwrap, locked: locked, key: key}), do: unwrap(locked, key)
  def act(input), do: Comn.unknown_action(input)

  # UUID helper (simple version)
  defmodule UUID do
    @moduledoc false
    @doc "Generates a random UUID v4 string."
    @spec uuid4() :: String.t()
    def uuid4 do
      <<u0::48, _::4, u1::12, _::2, u2::62>> = :crypto.strong_rand_bytes(16)

      <<u0::48, 4::4, u1::12, 2::2, u2::62>>
      |> Base.encode16(case: :lower)
      |> format_uuid()
    end

    defp format_uuid(<<p1::binary-8, p2::binary-4, p3::binary-4, p4::binary-4, p5::binary-12>>) do
      "#{p1}-#{p2}-#{p3}-#{p4}-#{p5}"
    end
  end
end
