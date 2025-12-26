defmodule Comn.Secrets.VaultTest do
  use ExUnit.Case

  alias Comn.Secrets.{Key, LockedBlob, Vault}

  # Only include SecurityTestCase when Vault is configured
  # SecurityTestCase tests require actual Vault encryption operations
  if System.get_env("VAULT_TOKEN") do
    use Comn.Secrets.SecurityTestCase, implementation: Comn.Secrets.Vault
  end

  # Vault-specific tests require a running Vault instance
  # Tag them so they can be excluded when Vault is unavailable
  @moduletag :vault_integration

  describe "Vault Transit engine integration (see features/vault_backend.feature)" do
    setup context do
      # Skip if Vault is not configured
      vault_addr = System.get_env("VAULT_ADDR") || "http://localhost:8200"
      vault_token = System.get_env("VAULT_TOKEN")

      if is_nil(vault_token) do
        :ok
      else
        # Create a test transit key
        key_name = "test-key-#{:erlang.unique_integer([:positive])}"

        # Generate Ed25519 key for local operations
        {pub, priv} = :crypto.generate_key(:eddsa, :ed25519)

        key = %Key{
          id: :crypto.hash(:blake2b, pub) |> binary_part(0, 16),
          algorithm: :ed25519,
          public: pub,
          private: priv,
          metadata: %{
            vault_addr: vault_addr,
            vault_token: vault_token,
            vault_key_name: key_name
          }
        }

        {:ok, key: key, key_name: key_name, vault_addr: vault_addr, vault_token: vault_token}
      end
    end

    test "lock and unlock with Vault Transit engine", context do
      key = context[:key]
      plaintext = "secret data"

      # Lock with Vault
      assert {:ok, locked} = Vault.lock(plaintext, key)
      assert %LockedBlob{} = locked

      # Should contain Vault-format ciphertext
      assert is_binary(locked.encrypted)
      assert is_binary(locked.nonce)
      assert is_binary(locked.tag)

      # Unlock with same key
      assert {:ok, ^plaintext} = Vault.unlock(locked, key)
    end

    test "Vault manages encryption keys, application never sees key material", context do
      key = context[:key]
      plaintext = "test data"

      # Lock operation should succeed
      assert {:ok, locked} = Vault.lock(plaintext, key)

      # The private key in our Key struct is never used for encryption with Vault
      # Vault manages the actual encryption key internally
      # Our key is just for authentication and key identification
      assert %LockedBlob{} = locked

      # Verify we can unlock
      assert {:ok, ^plaintext} = Vault.unlock(locked, key)
    end

    test "Vault ciphertext format is preserved in LockedBlob", context do
      key = context[:key]
      plaintext = "test data"

      assert {:ok, locked} = Vault.lock(plaintext, key)

      # Vault Transit returns base64-encoded ciphertext with "vault:v" prefix
      # This should be preserved in the encrypted field
      assert is_binary(locked.encrypted)

      # The cipher should indicate this is Vault-encrypted
      # (might be :vault_transit or similar)
      assert locked.cipher in [:vault_transit, :chacha20_poly1305, :aes_gcm]
    end

    test "Vault authentication token in key metadata", context do
      key = context[:key]
      plaintext = "secret data"

      # Token should be in metadata
      assert is_binary(key.metadata.vault_token)
      assert is_binary(key.metadata.vault_addr)

      # Lock should use the token from metadata
      assert {:ok, locked} = Vault.lock(plaintext, key)

      # Token should NOT appear in LockedBlob
      serialized = :erlang.term_to_binary(locked)
      refute serialized =~ key.metadata.vault_token,
        "Vault token leaked into LockedBlob!"
    end

    test "container wrap/unwrap with Vault", context do
      key = context[:key]
      # Lock three secrets
      {:ok, locked1} = Vault.lock("secret 1", key)
      {:ok, locked2} = Vault.lock("secret 2", key)
      {:ok, locked3} = Vault.lock("secret 3", key)

      blobs = [locked1, locked2, locked3]

      # Wrap in container
      assert {:ok, container_locked} = Vault.wrap(blobs, key)
      assert %LockedBlob{} = container_locked

      # Unwrap container
      assert {:ok, unwrapped_blobs} = Vault.unwrap(container_locked, key)
      assert length(unwrapped_blobs) == 3

      # Verify each blob can be unlocked
      assert {:ok, "secret 1"} = Vault.unlock(Enum.at(unwrapped_blobs, 0), key)
      assert {:ok, "secret 2"} = Vault.unlock(Enum.at(unwrapped_blobs, 1), key)
      assert {:ok, "secret 3"} = Vault.unlock(Enum.at(unwrapped_blobs, 2), key)
    end

    test "concurrent lock operations use Vault safely", context do
      key = context[:key]
      # Create 100 concurrent lock operations
      tasks =
        1..100
        |> Enum.map(fn i ->
          Task.async(fn ->
            Vault.lock("secret #{i}", key)
          end)
        end)

      # Wait for all to complete
      results = Enum.map(tasks, &Task.await(&1, 10_000))

      # All should succeed
      assert Enum.all?(results, fn
               {:ok, %LockedBlob{}} -> true
               _ -> false
             end)

      # Extract all nonces
      nonces =
        results
        |> Enum.map(fn {:ok, locked} -> locked.nonce end)

      # All nonces should be unique
      assert length(Enum.uniq(nonces)) == 100,
        "CRITICAL: Nonce reuse detected in concurrent operations!"

      # Verify all can be unlocked
      results
      |> Enum.with_index()
      |> Enum.each(fn {{:ok, locked}, i} ->
        expected = "secret #{i + 1}"
        assert {:ok, ^expected} = Vault.unlock(locked, key)
      end)
    end
  end

  describe "Vault error handling (see features/vault_backend.feature)" do
    test "Vault connection failures are handled gracefully" do
      # Create key with invalid Vault address
      {pub, priv} = :crypto.generate_key(:eddsa, :ed25519)

      key = %Key{
        id: :crypto.hash(:blake2b, pub) |> binary_part(0, 16),
        algorithm: :ed25519,
        public: pub,
        private: priv,
        metadata: %{
          vault_addr: "http://localhost:9999",
          vault_token: "invalid",
          vault_key_name: "test-key"
        }
      }

      # Should return error, not crash
      result = Vault.lock("secret data", key)

      assert {:error, reason} = result
      assert reason in [:vault_unavailable, :connection_failed, :network_error]

      # Error should not leak plaintext
      error_string = inspect(result)
      refute error_string =~ "secret data",
        "Plaintext leaked in error message!"
    end

    test "Vault-specific errors map to standard errors" do
      # Create key with valid address but invalid token
      vault_addr = System.get_env("VAULT_ADDR") || "http://localhost:8200"

      {pub, priv} = :crypto.generate_key(:eddsa, :ed25519)

      key = %Key{
        id: :crypto.hash(:blake2b, pub) |> binary_part(0, 16),
        algorithm: :ed25519,
        public: pub,
        private: priv,
        metadata: %{
          vault_addr: vault_addr,
          vault_token: "invalid-token",
          vault_key_name: "test-key"
        }
      }

      # Should return standard error
      result = Vault.lock("secret data", key)

      # Should be a standard error type, not Vault-specific
      assert {:error, reason} = result
      assert reason in [:authentication_failed, :invalid_key, :vault_unavailable]
    end
  end

  describe "backend interoperability (see features/backend_interoperability.feature)" do
    setup context do
      vault_addr = System.get_env("VAULT_ADDR") || "http://localhost:8200"
      vault_token = System.get_env("VAULT_TOKEN")

      if is_nil(vault_token) do
        :ok
      else
        key_name = "test-key-#{:erlang.unique_integer([:positive])}"
        {pub, priv} = :crypto.generate_key(:eddsa, :ed25519)

        # Same key struct for both backends
        key = %Key{
          id: :crypto.hash(:blake2b, pub) |> binary_part(0, 16),
          algorithm: :ed25519,
          public: pub,
          private: priv,
          metadata: %{
            vault_addr: vault_addr,
            vault_token: vault_token,
            vault_key_name: key_name
          }
        }

        {:ok, key: key}
      end
    end

    test "same interface across Local and Vault backends", context do
      key = context[:key]
      plaintext = "secret data"

      # Lock with both backends
      assert {:ok, local_locked} = Comn.Secrets.Local.lock(plaintext, key)
      assert {:ok, vault_locked} = Vault.lock(plaintext, key)

      # Both should return same struct type
      assert %LockedBlob{} = local_locked
      assert %LockedBlob{} = vault_locked

      # Both should have same struct fields
      local_fields = Map.keys(local_locked) |> Enum.sort()
      vault_fields = Map.keys(vault_locked) |> Enum.sort()
      assert local_fields == vault_fields

      # Both should unlock to same plaintext
      assert {:ok, ^plaintext} = Comn.Secrets.Local.unlock(local_locked, key)
      assert {:ok, ^plaintext} = Vault.unlock(vault_locked, key)
    end

    test "error types are standardized across backends", context do
      key = context[:key]
      # Create invalid key (wrong size)
      invalid_key = %Key{
        id: <<1, 2, 3>>,
        algorithm: :ed25519,
        public: :crypto.strong_rand_bytes(16),
        private: :crypto.strong_rand_bytes(32),
        metadata: key.metadata
      }

      # Both backends should return same error
      assert {:error, :invalid_key} = Comn.Secrets.Local.lock("data", invalid_key)
      assert {:error, :invalid_key} = Vault.lock("data", invalid_key)
    end
  end
end
