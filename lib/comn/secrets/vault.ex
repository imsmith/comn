defmodule Comn.Secrets.Vault do
  @moduledoc """
  HashiCorp Vault backend for Comn.Secrets using Transit secrets engine.

  This backend delegates encryption operations to Vault's Transit engine,
  which means the application never sees the actual encryption keys.
  Vault manages key material, versioning, and rotation internally.

  ## Configuration

  Vault-specific configuration is passed via key.metadata:
  - `vault_addr` - Vault server address (e.g., "http://localhost:8200")
  - `vault_token` - Authentication token for Vault
  - `vault_key_name` - Transit key name to use for encryption

  ## Security

  - Key material never leaves Vault
  - Nonce generation handled by Vault
  - Key rotation managed by Vault
  - All cryptographic operations performed server-side

  ## Interface Compatibility

  This module implements the same Comn.Secrets behavior as Local backend,
  ensuring the application interface remains constant regardless of backend.
  """

  @behaviour Comn.Secrets

  alias Comn.Secrets.{Key, LockedBlob, Container}

  require Logger

  @impl true
  def lock(blob, %Key{} = key) when is_binary(blob) do
    with :ok <- validate_key(key),
         {:ok, vault_config} <- extract_vault_config(key),
         {:ok, ciphertext} <- vault_encrypt(blob, vault_config) do
      # Parse Vault's ciphertext format
      # Vault returns format like "vault:v1:base64data"
      # We need to extract metadata from this

      metadata = %{
        created_at: DateTime.utc_now() |> DateTime.to_iso8601(),
        algorithm: key.algorithm,
        vault_key_name: vault_config.key_name,
        vault_version: extract_vault_version(ciphertext)
      }

      # Generate a nonce for our LockedBlob structure
      # Note: Vault handles nonces internally, but we include one
      # for interface compatibility
      nonce = :crypto.strong_rand_bytes(12)

      # Extract the actual ciphertext portion
      # Vault format: "vault:v1:base64_ciphertext"
      # The ciphertext already includes Vault's internal nonce
      encrypted = ciphertext

      # For Vault, we don't have a separate tag since Vault
      # handles authentication internally. We'll use empty tag
      # or extract from Vault's format if possible
      tag = <<>>

      locked = %LockedBlob{
        cipher: :vault_transit,
        encrypted: encrypted,
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
    with :ok <- validate_key(key),
         true <- Key.fingerprint_matches?(locked.key_hint, key),
         {:ok, vault_config} <- extract_vault_config(key),
         {:ok, plaintext} <- vault_decrypt(locked.encrypted, vault_config) do
      {:ok, plaintext}
    else
      false ->
        {:error, :wrong_key}

      {:error, reason} ->
        {:error, reason}

      :error ->
        {:error, :invalid_key}
    end
  end

  def unlock(_locked, _key), do: {:error, :invalid_key}

  @impl true
  def wrap(blobs, %Key{} = key) when is_list(blobs) do
    with :ok <- validate_key(key) do
      container = %Container{
        id: Comn.Secrets.Local.UUID.uuid4(),
        blobs: blobs,
        metadata: %{
          created_at: DateTime.utc_now() |> DateTime.to_iso8601(),
          blob_count: length(blobs)
        }
      }

      serialized = :erlang.term_to_binary(container)
      lock(serialized, key)
    end
  end

  @impl true
  def unwrap(%LockedBlob{} = locked_container, %Key{} = key) do
    case validate_key(key) do
      :ok ->
        case unlock(locked_container, key) do
          {:ok, serialized} ->
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

  defp extract_vault_config(%Key{metadata: metadata}) do
    case metadata do
      %{vault_addr: addr, vault_token: token, vault_key_name: key_name}
      when is_binary(addr) and is_binary(token) and is_binary(key_name) ->
        {:ok,
         %{
           addr: addr,
           token: token,
           key_name: key_name
         }}

      _ ->
        {:error, :invalid_vault_config}
    end
  end

  defp vault_encrypt(plaintext, vault_config) do
    # Vault Transit encrypt endpoint
    url = "#{vault_config.addr}/v1/transit/encrypt/#{vault_config.key_name}"

    # Base64 encode the plaintext (Vault requirement)
    encoded_plaintext = Base.encode64(plaintext)

    # Prepare request body
    body = Jason.encode!(%{"plaintext" => encoded_plaintext})

    headers = [
      {'X-Vault-Token', String.to_charlist(vault_config.token)},
      {'Content-Type', 'application/json'}
    ]

    # Make HTTP request
    case http_post(url, headers, body) do
      {:ok, response_body} ->
        case Jason.decode(response_body) do
          {:ok, %{"data" => %{"ciphertext" => ciphertext}}} ->
            {:ok, ciphertext}

          {:ok, %{"errors" => errors}} ->
            Logger.error("Vault encryption failed: #{inspect(errors)}")
            map_vault_error(errors)

          _ ->
            {:error, :vault_error}
        end

      {:error, reason} ->
        Logger.error("Vault HTTP request failed: #{inspect(reason)}")
        {:error, :vault_unavailable}
    end
  end

  defp vault_decrypt(ciphertext, vault_config) do
    # Vault Transit decrypt endpoint
    url = "#{vault_config.addr}/v1/transit/decrypt/#{vault_config.key_name}"

    # Prepare request body
    body = Jason.encode!(%{"ciphertext" => ciphertext})

    headers = [
      {'X-Vault-Token', String.to_charlist(vault_config.token)},
      {'Content-Type', 'application/json'}
    ]

    # Make HTTP request
    case http_post(url, headers, body) do
      {:ok, response_body} ->
        case Jason.decode(response_body) do
          {:ok, %{"data" => %{"plaintext" => encoded_plaintext}}} ->
            # Base64 decode the plaintext
            case Base.decode64(encoded_plaintext) do
              {:ok, plaintext} -> {:ok, plaintext}
              :error -> {:error, :invalid_ciphertext}
            end

          {:ok, %{"errors" => errors}} ->
            Logger.error("Vault decryption failed: #{inspect(errors)}")
            map_vault_error(errors)

          _ ->
            {:error, :vault_error}
        end

      {:error, reason} ->
        Logger.error("Vault HTTP request failed: #{inspect(reason)}")
        {:error, :vault_unavailable}
    end
  end

  defp http_post(url, headers, body) do
    # Start inets if not already started
    :inets.start()

    url_charlist = String.to_charlist(url)
    body_charlist = String.to_charlist(body)

    case :httpc.request(:post, {url_charlist, headers, 'application/json', body_charlist}, [], []) do
      {:ok, {{_, 200, _}, _headers, response_body}} ->
        {:ok, to_string(response_body)}

      {:ok, {{_, status_code, _}, _headers, response_body}} ->
        Logger.error("Vault returned status #{status_code}: #{response_body}")
        {:error, :vault_error}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    e ->
      Logger.error("HTTP request exception: #{inspect(e)}")
      {:error, :network_error}
  end

  defp extract_vault_version(ciphertext) do
    # Vault format: "vault:v1:..." or "vault:v2:..."
    case String.split(ciphertext, ":", parts: 3) do
      ["vault", version, _] -> version
      _ -> "unknown"
    end
  end

  defp map_vault_error(errors) when is_list(errors) do
    # Map common Vault errors to standard error types
    error_string = Enum.join(errors, " ") |> String.downcase()

    cond do
      String.contains?(error_string, "permission denied") ->
        {:error, :authentication_failed}

      String.contains?(error_string, "invalid token") ->
        {:error, :authentication_failed}

      String.contains?(error_string, "missing") ->
        {:error, :invalid_key}

      true ->
        {:error, :vault_error}
    end
  end

  defp map_vault_error(_), do: {:error, :vault_error}
end
