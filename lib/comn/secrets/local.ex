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

  alias Comn.Secrets.{Key, LockedBlob, Container}
  alias Comn.Errors.Registry, as: ErrReg

  @impl true
  def lock(blob, %Key{} = key) when is_binary(blob) do
    # Validate key first
    with :ok <- validate_key(key) do
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
      {ciphertext, tag} = :crypto.crypto_one_time_aead(
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
    with :ok <- validate_key(key),
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
  def wrap(blobs, %Key{} = key) when is_list(blobs) do
    # Validate key
    with :ok <- validate_key(key) do
      # Create container
      container = %Container{
        id: Comn.Secrets.Local.UUID.uuid4(),
        blobs: blobs,
        metadata: %{
          created_at: DateTime.utc_now() |> DateTime.to_iso8601(),
          blob_count: length(blobs)
        }
      }

      # Serialize container
      serialized = :erlang.term_to_binary(container)

      # Encrypt the entire serialized container (lock operation)
      lock(serialized, key)
    end
  end

  @impl true
  def unwrap(%LockedBlob{} = locked_container, %Key{} = key) do
    case validate_key(key) do
      :ok ->
        case unlock(locked_container, key) do
          {:ok, serialized} ->
            # Deserialize safely
            try do
              container = :erlang.binary_to_term(serialized, [:safe])

              case container do
                %Container{blobs: blobs} when is_list(blobs) ->
                  {:ok, blobs}

                _ ->
                  {:error, ErrReg.error!("secrets/invalid_container")}
              end
            rescue
              ArgumentError -> {:error, ErrReg.error!("secrets/invalid_container")}
            end

          {:error, _reason} = error ->
            error
        end

      error ->
        error
    end
  end

  # Private helpers

  defp validate_key(%Key{algorithm: :ed25519, public: pub, private: priv})
       when is_binary(pub) and is_binary(priv) do
    cond do
      byte_size(pub) != 32 ->
        {:error, ErrReg.error!("secrets/invalid_key")}

      byte_size(priv) != 32 ->
        {:error, ErrReg.error!("secrets/invalid_key")}

      true ->
        :ok
    end
  end

  defp validate_key(%Key{algorithm: :ed25519, private: nil}) do
    {:error, ErrReg.error!("secrets/invalid_key")}
  end

  defp validate_key(%Key{algorithm: :rsa_4096}) do
    # RSA not implemented yet
    {:error, ErrReg.error!("secrets/invalid_key")}
  end

  defp validate_key(%Key{algorithm: :ecdsa_p256}) do
    # ECDSA not implemented yet
    {:error, ErrReg.error!("secrets/invalid_key")}
  end

  defp validate_key(_), do: {:error, ErrReg.error!("secrets/invalid_key")}

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
  def act(_input), do: {:error, :unknown_action}

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
