defmodule Comn.Secrets.GPGKeyTest do
  use ExUnit.Case, async: true
  alias Comn.Errors.ErrorStruct
  alias Comn.Secrets.{Key, Utils}

  @fpr :crypto.strong_rand_bytes(20)

  test "fingerprint byte 0x04 round-trips" do
    key = %Key{algorithm: :gpg, public: @fpr}
    assert <<0x04, _::binary-16>> = Key.fingerprint(key)
    assert Key.algorithm_from_fingerprint(Key.fingerprint(key)) == :gpg
  end

  test "recipient key: 20- or 32-byte public, nil private" do
    assert :ok = Utils.validate_key(%Key{algorithm: :gpg, public: @fpr})
    assert :ok = Utils.validate_key(%Key{algorithm: :gpg, public: :crypto.strong_rand_bytes(32)})

    assert {:error, %ErrorStruct{code: "secrets/invalid_key"}} =
             Utils.validate_key(%Key{algorithm: :gpg, public: :crypto.strong_rand_bytes(16)})

    assert {:error, %ErrorStruct{code: "secrets/invalid_key"}} =
             Utils.validate_key(%Key{algorithm: :gpg, public: @fpr, private: "x"})
  end

  test "symmetric key: non-empty label and passphrase, no newline" do
    sym = %Key{algorithm: :gpg, public: "label", private: "pw", metadata: %{mode: :symmetric}}
    assert :ok = Utils.validate_key(sym)

    for bad <- [
          %{sym | private: nil},
          %{sym | private: ""},
          %{sym | public: ""},
          %{sym | private: "a\nb"},
          %{sym | private: "a\0b"}
        ] do
      assert {:error, %ErrorStruct{code: "secrets/invalid_key"}} = Utils.validate_key(bad)
    end
  end

  test "gpg_fingerprint_hex normalizes and rejects" do
    assert {:ok, String.duplicate("AB", 20)} ==
             Utils.gpg_fingerprint_hex("ab ab " <> String.duplicate("ab", 18))

    assert {:ok, String.duplicate("0F", 32)} ==
             Utils.gpg_fingerprint_hex(String.duplicate("0f", 32))

    assert {:error, %ErrorStruct{code: "secrets/invalid_gpg_config"}} =
             Utils.gpg_fingerprint_hex("zz")

    assert {:error, %ErrorStruct{code: "secrets/invalid_gpg_config"}} =
             Utils.gpg_fingerprint_hex(String.duplicate("ab", 19))
  end

  test "new error codes are registered" do
    for code <- ~w(secrets/invalid_gpg_config secrets/gpg_unavailable secrets/gpg_error) do
      assert %ErrorStruct{code: ^code} = Comn.Errors.Registry.error!(code)
    end
  end
end
