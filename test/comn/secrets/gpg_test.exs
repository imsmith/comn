defmodule Comn.Secrets.GPGTest do
  use ExUnit.Case
  @moduletag :gpg
  import Comn.Secrets.GPGHelpers
  alias Comn.Errors.ErrorStruct
  alias Comn.Secrets.{GPG, Key, LockedBlob}

  setup do
    home = homedir!()
    fpr = gen_key!(home)
    {:ok, home: home, fpr: fpr, key: recipient_key(home, fpr)}
  end

  test "helper generates a usable key", %{home: home, fpr: fpr} do
    assert String.length(fpr) in [40, 64]
    assert Bitwise.band(File.stat!(home).mode, 0o777) == 0o700
  end

  describe "recipient mode" do
    test "armored round trip and gpg -d interop", %{key: key, home: home} do
      assert {:ok, %LockedBlob{cipher: :gpg, tag: nil, nonce: nil} = locked} =
               GPG.lock("hello", key)

      assert String.starts_with?(locked.encrypted, "-----BEGIN PGP MESSAGE-----")
      assert locked.metadata.armor == true
      assert locked.metadata.mode == :recipient
      assert locked.metadata.signed == false
      assert locked.key_hint == Key.fingerprint(key)
      assert {:ok, "hello"} = GPG.unlock(locked, key)
      assert shell_decrypt!(home, locked.encrypted) == "hello"
    end

    test "binary output", %{key: key} do
      key = %{key | metadata: Map.put(key.metadata, :armor, false)}
      assert {:ok, locked} = GPG.lock("hello", key)
      refute String.starts_with?(locked.encrypted, "-----BEGIN")
      assert locked.metadata.armor == false
      assert {:ok, "hello"} = GPG.unlock(locked, key)
    end

    test "empty plaintext round-trips", %{key: key} do
      assert {:ok, locked} = GPG.lock("", key)
      assert {:ok, ""} = GPG.unlock(locked, key)
    end

    test "extra recipient can unlock", %{key: key, home: home} do
      fpr2 = gen_key!(home, "Second <two@comn.invalid>")
      key = %{key | metadata: Map.put(key.metadata, :recipients, [String.downcase(fpr2)])}
      assert {:ok, locked} = GPG.lock("hello", key)
      assert locked.metadata.recipients == [Base.encode16(key.public), fpr2]
      assert {:ok, "hello"} = GPG.unlock(locked, recipient_key(home, fpr2))
    end

    test "wrong key is secrets/wrong_key", %{key: key} do
      other_home = homedir!()
      other = recipient_key(other_home, gen_key!(other_home))
      assert {:ok, locked} = GPG.lock("hello", key)
      assert {:error, %ErrorStruct{code: "secrets/wrong_key"}} = GPG.unlock(locked, other)
      # no hint: gpg decides, and the other homedir has no matching secret key
      assert {:error, %ErrorStruct{code: "secrets/wrong_key"}} =
               GPG.unlock(%{locked | key_hint: nil}, other)
    end

    test "tampered packets never unlock", %{key: key} do
      key = %{key | metadata: Map.put(key.metadata, :armor, false)}
      assert {:ok, locked} = GPG.lock("hello", key)
      <<head::binary-size(40), b, rest::binary>> = locked.encrypted
      bad = %{locked | encrypted: head <> <<Bitwise.bxor(b, 0xFF)>> <> rest}
      assert {:error, %ErrorStruct{code: code}} = GPG.unlock(bad, key)

      assert code in [
               "secrets/authentication_failed",
               "secrets/invalid_ciphertext",
               "secrets/wrong_key"
             ]
    end

    test "bad config", %{key: key} do
      bad = %{key | metadata: Map.put(key.metadata, :recipients, ["nope"])}
      assert {:error, %ErrorStruct{code: "secrets/invalid_gpg_config"}} = GPG.lock("x", bad)
      missing = %{key | metadata: Map.put(key.metadata, :homedir, "/nonexistent/dir")}
      assert {:error, %ErrorStruct{code: "secrets/invalid_gpg_config"}} = GPG.lock("x", missing)
      nobin = %{key | metadata: Map.put(key.metadata, :gpg_path, "/nonexistent/gpg")}
      assert {:error, %ErrorStruct{code: "secrets/invalid_gpg_config"}} = GPG.lock("x", nobin)
    end

    test "non-gpg key is secrets/invalid_key" do
      {pub, priv} = :crypto.generate_key(:eddsa, :ed25519)

      assert {:error, %ErrorStruct{code: "secrets/invalid_key"}} =
               GPG.lock("x", %Key{algorithm: :ed25519, public: pub, private: priv})
    end

    test "hung gpg is secrets/gpg_error after the timeout", %{key: key, home: home} do
      stub = Path.join(home, "slow-gpg")
      File.write!(stub, "#!/bin/sh\nsleep 5\n")
      File.chmod!(stub, 0o700)
      key = %{key | metadata: Map.merge(key.metadata, %{gpg_path: stub, timeout_ms: 200})}
      assert {:error, %ErrorStruct{code: "secrets/gpg_error"}} = GPG.lock("x", key)

      refute Enum.any?(
               File.ls!(System.tmp_dir!()),
               &String.starts_with?(&1, "comn_gpg_status_")
             )
    end
  end

  describe "symmetric mode" do
    test "round trip, armored, and gpg -d interop", %{home: home} do
      key = symmetric_key("correct horse", %{homedir: home})

      assert {:ok, %LockedBlob{metadata: %{mode: :symmetric}} = locked} =
               GPG.lock("hello\nworld", key)

      assert {:ok, "hello\nworld"} = GPG.unlock(locked, key)
      assert locked.key_hint == Key.fingerprint(key)
    end

    test "wrong passphrase is secrets/wrong_key", %{home: home} do
      key = symmetric_key("one", %{homedir: home})
      assert {:ok, locked} = GPG.lock("hello", key)

      assert {:error, %ErrorStruct{code: "secrets/wrong_key"}} =
               GPG.unlock(%{locked | key_hint: nil}, symmetric_key("two", %{homedir: home}))
    end

    test "sign: true is a config error in symmetric mode", %{home: home} do
      key = symmetric_key("pw", %{homedir: home, sign: true})
      assert {:error, %ErrorStruct{code: "secrets/invalid_gpg_config"}} = GPG.lock("x", key)
    end
  end
end
