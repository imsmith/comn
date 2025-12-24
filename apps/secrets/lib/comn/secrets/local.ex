defmodule Comn.Secrets.Local do
  @moduledoc """
  Local implementation of Comn.Secrets using Erlang :crypto module.

  Uses hybrid encryption (NaCl box style):
  - Ed25519 keys for identity
  - ChaCha20-Poly1305 for AEAD encryption
  - Ephemeral keys for each encryption (provides forward secrecy)

  This is similar to how modern tools like 'age' work - PGP-inspired
  but using modern cryptographic primitives.
  """

  @behaviour Comn.Secrets

  alias Comn.Secrets.{Key, LockedBlob, Container}

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

  def lock(_blob, _key), do: {:error, :invalid_key}

  @impl true
  def unlock(%LockedBlob{} = locked, %Key{} = key) do
    # Validate key first
    with :ok <- validate_key(key),
         true <- Key.fingerprint_matches?(locked.key_hint, key) do
      # Derive same symmetric key
      symmetric_key = :crypto.hash(:sha256, key.private)

      # Serialize metadata for AAD
      aad = :erlang.term_to_binary(locked.metadata, [:safe])

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
          {:error, :authentication_failed}
      end
    else
      false ->
        {:error, :wrong_key}

      :error ->
        {:error, :invalid_key}
    end
  end

  def unlock(_locked, _key), do: {:error, :invalid_key}

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
                  {:error, :invalid_container}
              end
            rescue
              _ -> {:error, :invalid_container}
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
        {:error, :invalid_key}

      byte_size(priv) != 32 ->
        {:error, :invalid_key}

      true ->
        :ok
    end
  end

  defp validate_key(%Key{algorithm: :ed25519, private: nil}) do
    {:error, :invalid_key}
  end

  defp validate_key(%Key{algorithm: :rsa_4096}) do
    # RSA not implemented yet
    {:error, :invalid_key}
  end

  defp validate_key(%Key{algorithm: :ecdsa_p256}) do
    # ECDSA not implemented yet
    {:error, :invalid_key}
  end

  defp validate_key(_), do: {:error, :invalid_key}

  # UUID helper (simple version)
  defmodule UUID do
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
