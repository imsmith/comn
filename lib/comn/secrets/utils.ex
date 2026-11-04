defmodule Comn.Secrets.Utils do
  @moduledoc """
  Shared helpers for `Comn.Secrets` implementations.

  Key validation and container wrap/unwrap are backend-independent: a
  container is a `Comn.Secrets.Container` serialized with
  `:erlang.term_to_binary/1` and then locked like any other blob. Backends
  supply only `lock/2` and `unlock/2`; the helpers here call back into the
  backend module for those.
  """

  alias Comn.Errors.Registry, as: ErrReg
  alias Comn.Secrets.{Container, Key, LockedBlob}
  alias Comn.Secrets.Local.UUID

  @doc """
  Validates a key's structure against its algorithm.

  Accepts a well-formed Ed25519 key pair and the two `:gpg` shapes used by
  `Comn.Secrets.GPG`: a recipient key (`public` is a 20- or 32-byte raw
  fingerprint, `private` is nil) and a symmetric key (`metadata.mode` is
  `:symmetric`, `public` is a non-empty label, `private` is a non-empty
  passphrase without a newline).

  Errors: `secrets/invalid_key` for anything else. RSA-4096 and ECDSA-P256
  are not implemented and are rejected.
  """
  @spec validate_key(term()) :: :ok | {:error, Comn.Errors.ErrorStruct.t()}
  def validate_key(%Key{algorithm: :ed25519, public: pub, private: priv})
      when is_binary(pub) and is_binary(priv) do
    if byte_size(pub) == 32 and byte_size(priv) == 32,
      do: :ok,
      else: {:error, ErrReg.error!("secrets/invalid_key")}
  end

  def validate_key(%Key{
        algorithm: :gpg,
        metadata: %{mode: :symmetric},
        public: label,
        private: pw
      })
      when is_binary(label) and label != "" and is_binary(pw) and pw != "" do
    if String.contains?(pw, "\n"),
      do: {:error, ErrReg.error!("secrets/invalid_key")},
      else: :ok
  end

  def validate_key(%Key{algorithm: :gpg, metadata: %{mode: :symmetric}}),
    do: {:error, ErrReg.error!("secrets/invalid_key")}

  def validate_key(%Key{algorithm: :gpg, public: fpr, private: nil})
      when is_binary(fpr) and byte_size(fpr) in [20, 32],
      do: :ok

  def validate_key(_), do: {:error, ErrReg.error!("secrets/invalid_key")}

  @doc """
  Normalizes an OpenPGP fingerprint given as hex: strips whitespace, upcases,
  and requires exactly 40 (v4) or 64 (v5) hex characters.

  Errors: `secrets/invalid_gpg_config`.
  """
  @spec gpg_fingerprint_hex(term()) :: {:ok, String.t()} | {:error, Comn.Errors.ErrorStruct.t()}
  def gpg_fingerprint_hex(hex) when is_binary(hex) do
    norm = hex |> String.replace(~r/\s/, "") |> String.upcase()

    if Regex.match?(~r/\A(?:[0-9A-F]{40}|[0-9A-F]{64})\z/, norm),
      do: {:ok, norm},
      else: {:error, ErrReg.error!("secrets/invalid_gpg_config")}
  end

  def gpg_fingerprint_hex(_), do: {:error, ErrReg.error!("secrets/invalid_gpg_config")}

  @doc """
  Bundles `blobs` into a `Container` and locks it with `backend.lock/2`.

  Errors: `secrets/invalid_key`, plus whatever `backend.lock/2` returns.
  """
  @spec wrap(module(), [LockedBlob.t()], Key.t()) ::
          {:ok, LockedBlob.t()} | {:error, Comn.Errors.ErrorStruct.t()}
  def wrap(backend, blobs, %Key{} = key) when is_list(blobs) do
    with :ok <- validate_key(key) do
      container = %Container{
        id: UUID.uuid4(),
        blobs: blobs,
        metadata: %{
          created_at: DateTime.to_iso8601(DateTime.utc_now()),
          blob_count: length(blobs)
        }
      }

      backend.lock(:erlang.term_to_binary(container), key)
    end
  end

  @doc """
  Unlocks a container with `backend.unlock/2` and returns its blobs.

  Errors: `secrets/invalid_key`, `secrets/invalid_container` when the
  decrypted bytes are not a `Container`, plus whatever `backend.unlock/2`
  returns.
  """
  @spec unwrap(module(), LockedBlob.t(), Key.t()) ::
          {:ok, [LockedBlob.t()]} | {:error, Comn.Errors.ErrorStruct.t()}
  def unwrap(backend, %LockedBlob{} = locked, %Key{} = key) do
    with :ok <- validate_key(key),
         {:ok, serialized} <- backend.unlock(locked, key) do
      deserialize(serialized)
    end
  end

  defp deserialize(serialized) do
    case Plug.Crypto.non_executable_binary_to_term(serialized, [:safe]) do
      %Container{blobs: blobs} when is_list(blobs) -> {:ok, blobs}
      _ -> {:error, ErrReg.error!("secrets/invalid_container")}
    end
  rescue
    ArgumentError -> {:error, ErrReg.error!("secrets/invalid_container")}
  end
end
