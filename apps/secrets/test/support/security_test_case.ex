defmodule Comn.Secrets.SecurityTestCase do
  @moduledoc """
  Shared security tests for Comn.Secrets implementations.

  Any module implementing the Comn.Secrets behavior should use these tests
  to verify it meets security requirements defined in the Gherkin feature files.

  ## Usage

      defmodule MyApp.Secrets.LocalTest do
        use ExUnit.Case
        use Comn.Secrets.SecurityTestCase, implementation: MyApp.Secrets.Local
      end
  """

  defmacro __using__(opts) do
    implementation = Keyword.fetch!(opts, :implementation)

    quote bind_quoted: [implementation: implementation] do
      use Bitwise
      alias Comn.Secrets.{Key, LockedBlob, Container}

      describe "key validation (see features/key_validation.feature)" do
        test "rejects Ed25519 key with wrong private key size" do
          key = %Key{
            id: <<1, 2, 3>>,
            algorithm: :ed25519,
            public: :crypto.strong_rand_bytes(32),
            private: :crypto.strong_rand_bytes(16)
          }

          result = unquote(implementation).lock("secret data", key)
          
          assert {:error, :invalid_key} = result
        end

        test "rejects Ed25519 key with wrong public key size" do
          key = %Key{
            id: <<1, 2, 3>>,
            algorithm: :ed25519,
            public: :crypto.strong_rand_bytes(16),
            private: :crypto.strong_rand_bytes(32)
          }

          result = unquote(implementation).lock("secret data", key)
          
          assert {:error, :invalid_key} = result
        end

        test "rejects key with missing private key when needed for encryption" do
          key = %Key{
            id: <<1, 2, 3>>,
            algorithm: :ed25519,
            public: :crypto.strong_rand_bytes(32),
            private: nil
          }

          result = unquote(implementation).lock("secret data", key)
          
          assert {:error, :invalid_key} = result
        end

        test "rejects key with algorithm/size mismatch" do
          key = %Key{
            id: <<1, 2, 3>>,
            algorithm: :rsa_4096,
            public: :crypto.strong_rand_bytes(32),
            private: :crypto.strong_rand_bytes(32)
          }

          result = unquote(implementation).lock("secret data", key)
          
          assert {:error, :invalid_key} = result
        end

        test "accepts valid Ed25519 key" do
          {pub, priv} = :crypto.generate_key(:eddsa, :ed25519)
          
          key = %Key{
            id: :crypto.hash(:blake2b, pub) |> binary_part(0, 16),
            algorithm: :ed25519,
            public: pub,
            private: priv
          }

          result = unquote(implementation).lock("secret data", key)
          
          assert {:ok, %LockedBlob{}} = result
        end
      end

      describe "nonce uniqueness (see features/nonce_uniqueness.feature)" do
        setup do
          {pub, priv} = :crypto.generate_key(:eddsa, :ed25519)
          
          key = %Key{
            id: :crypto.hash(:blake2b, pub) |> binary_part(0, 16),
            algorithm: :ed25519,
            public: pub,
            private: priv
          }

          {:ok, key: key}
        end

        test "same plaintext produces different ciphertexts", %{key: key} do
          plaintext = "identical secret data"
          
          {:ok, locked1} = unquote(implementation).lock(plaintext, key)
          {:ok, locked2} = unquote(implementation).lock(plaintext, key)
          
          refute locked1.nonce == locked2.nonce,
            "CRITICAL: Nonce reuse detected!"
          
          refute locked1.encrypted == locked2.nonce,
            "CRITICAL: Deterministic encryption detected!"
        end

        test "nonces have sufficient length", %{key: key} do
          {:ok, locked} = unquote(implementation).lock("secret data", key)
          
          assert byte_size(locked.nonce) >= 12,
            "Nonce too short"
        end
      end
    end
  end
end
