defmodule Comn.Secrets.EdgeCasesTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias Comn.Errors.ErrorStruct
  alias Comn.Secrets.{Local, Key, LockedBlob}

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

  describe "lock/unlock round-trip" do
    test "empty binary", %{key: key} do
      {:ok, locked} = Local.lock("", key)
      {:ok, ""} = Local.unlock(locked, key)
    end

    test "single byte", %{key: key} do
      {:ok, locked} = Local.lock(<<0>>, key)
      {:ok, <<0>>} = Local.unlock(locked, key)
    end

    test "large payload (1MB)", %{key: key} do
      payload = :crypto.strong_rand_bytes(1_000_000)
      {:ok, locked} = Local.lock(payload, key)
      {:ok, ^payload} = Local.unlock(locked, key)
    end

    test "binary with null bytes", %{key: key} do
      payload = <<0, 0, 0, 1, 0, 0, 0, 2>>
      {:ok, locked} = Local.lock(payload, key)
      {:ok, ^payload} = Local.unlock(locked, key)
    end

    test "UTF-8 text", %{key: key} do
      payload = "héllo wörld 日本語"
      {:ok, locked} = Local.lock(payload, key)
      {:ok, ^payload} = Local.unlock(locked, key)
    end
  end

  describe "wrong key on unlock" do
    test "different key pair returns :wrong_key", %{key: key} do
      {:ok, locked} = Local.lock("secret", key)

      {pub2, priv2} = :crypto.generate_key(:eddsa, :ed25519)
      other_key = %Key{
        id: :crypto.hash(:blake2b, pub2) |> binary_part(0, 16),
        algorithm: :ed25519,
        public: pub2,
        private: priv2
      }

      assert {:error, %ErrorStruct{code: "secrets/wrong_key"}} = Local.unlock(locked, other_key)
    end
  end

  describe "corrupted ciphertext" do
    test "flipped bit in ciphertext fails authentication", %{key: key} do
      {:ok, locked} = Local.lock("secret", key)

      <<first_byte, rest::binary>> = locked.encrypted
      corrupted = <<Bitwise.bxor(first_byte, 0xFF), rest::binary>>
      tampered = %{locked | encrypted: corrupted}

      assert {:error, %ErrorStruct{code: "secrets/authentication_failed"}} = Local.unlock(tampered, key)
    end

    test "flipped bit in tag fails authentication", %{key: key} do
      {:ok, locked} = Local.lock("secret", key)

      <<first_byte, rest::binary>> = locked.tag
      corrupted = <<Bitwise.bxor(first_byte, 0xFF), rest::binary>>
      tampered = %{locked | tag: corrupted}

      assert {:error, %ErrorStruct{code: "secrets/authentication_failed"}} = Local.unlock(tampered, key)
    end

    test "wrong nonce fails authentication", %{key: key} do
      {:ok, locked} = Local.lock("secret", key)

      tampered = %{locked | nonce: :crypto.strong_rand_bytes(12)}

      assert {:error, %ErrorStruct{code: "secrets/authentication_failed"}} = Local.unlock(tampered, key)
    end
  end

  describe "wrap/unwrap round-trip" do
    test "wraps and unwraps multiple blobs", %{key: key} do
      {:ok, blob1} = Local.lock("first", key)
      {:ok, blob2} = Local.lock("second", key)
      {:ok, blob3} = Local.lock("third", key)

      {:ok, container} = Local.wrap([blob1, blob2, blob3], key)
      assert %LockedBlob{} = container

      {:ok, unwrapped} = Local.unwrap(container, key)
      assert length(unwrapped) == 3

      # Verify the blobs are identical
      {:ok, "first"} = Local.unlock(Enum.at(unwrapped, 0), key)
      {:ok, "second"} = Local.unlock(Enum.at(unwrapped, 1), key)
      {:ok, "third"} = Local.unlock(Enum.at(unwrapped, 2), key)
    end

    test "wraps empty list", %{key: key} do
      {:ok, container} = Local.wrap([], key)
      {:ok, []} = Local.unwrap(container, key)
    end

    test "unwrap with wrong key fails", %{key: key} do
      {:ok, blob} = Local.lock("secret", key)
      {:ok, container} = Local.wrap([blob], key)

      {pub2, priv2} = :crypto.generate_key(:eddsa, :ed25519)
      other_key = %Key{
        id: :crypto.hash(:blake2b, pub2) |> binary_part(0, 16),
        algorithm: :ed25519,
        public: pub2,
        private: priv2
      }

      assert {:error, %ErrorStruct{code: "secrets/wrong_key"}} = Local.unwrap(container, other_key)
    end

    test "corrupted container fails authentication", %{key: key} do
      {:ok, blob} = Local.lock("secret", key)
      {:ok, container} = Local.wrap([blob], key)

      <<first_byte, rest::binary>> = container.encrypted
      corrupted = <<Bitwise.bxor(first_byte, 0xFF), rest::binary>>
      tampered = %{container | encrypted: corrupted}

      assert {:error, %ErrorStruct{code: "secrets/authentication_failed"}} = Local.unlock(tampered, key)
    end
  end

  describe "non-binary input" do
    test "lock rejects non-binary", %{key: key} do
      assert {:error, %ErrorStruct{code: "secrets/invalid_key"}} = Local.lock(123, key)
      assert {:error, %ErrorStruct{code: "secrets/invalid_key"}} = Local.lock(:atom, key)
      assert {:error, %ErrorStruct{code: "secrets/invalid_key"}} = Local.lock([1, 2], key)
    end

    test "unlock rejects non-LockedBlob" do
      {pub, priv} = :crypto.generate_key(:eddsa, :ed25519)
      key = %Key{algorithm: :ed25519, public: pub, private: priv}

      assert {:error, %ErrorStruct{code: "secrets/invalid_key"}} = Local.unlock("not a blob", key)
      assert {:error, %ErrorStruct{code: "secrets/invalid_key"}} = Local.unlock(%{}, key)
    end
  end
end
