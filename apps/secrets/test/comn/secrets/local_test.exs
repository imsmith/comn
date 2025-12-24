defmodule Comn.Secrets.LocalTest do
  use ExUnit.Case
  use Comn.Secrets.SecurityTestCase, implementation: Comn.Secrets.Local

  # All 20 security tests are automatically included from SecurityTestCase
  
  # Add implementation-specific tests here
  describe "Local implementation specifics" do
    test "uses ChaCha20-Poly1305 cipher" do
      {pub, priv} = :crypto.generate_key(:eddsa, :ed25519)
      
      key = %Comn.Secrets.Key{
        id: :crypto.hash(:blake2b, pub) |> binary_part(0, 16),
        algorithm: :ed25519,
        public: pub,
        private: priv
      }

      {:ok, locked} = Comn.Secrets.Local.lock("test data", key)
      
      assert locked.cipher == :chacha20_poly1305
    end

    test "generates 12-byte nonces" do
      {pub, priv} = :crypto.generate_key(:eddsa, :ed25519)
      
      key = %Comn.Secrets.Key{
        id: :crypto.hash(:blake2b, pub) |> binary_part(0, 16),
        algorithm: :ed25519,
        public: pub,
        private: priv
      }

      {:ok, locked} = Comn.Secrets.Local.lock("test data", key)
      
      assert byte_size(locked.nonce) == 12
    end

    test "includes metadata with timestamp" do
      {pub, priv} = :crypto.generate_key(:eddsa, :ed25519)
      
      key = %Comn.Secrets.Key{
        id: :crypto.hash(:blake2b, pub) |> binary_part(0, 16),
        algorithm: :ed25519,
        public: pub,
        private: priv
      }

      {:ok, locked} = Comn.Secrets.Local.lock("test data", key)
      
      assert Map.has_key?(locked.metadata, :created_at)
      assert Map.has_key?(locked.metadata, :algorithm)
      assert locked.metadata.algorithm == :ed25519
    end
  end
end
