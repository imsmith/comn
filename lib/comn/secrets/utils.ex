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

  Errors: `secrets/invalid_key` for anything but a well-formed Ed25519 key
  pair. RSA-4096 and ECDSA-P256 are not implemented and are rejected.
  """
  @spec validate_key(term()) :: :ok | {:error, Comn.Errors.ErrorStruct.t()}
  def validate_key(%Key{algorithm: :ed25519, public: pub, private: priv})
      when is_binary(pub) and is_binary(priv) do
    if byte_size(pub) == 32 and byte_size(priv) == 32,
      do: :ok,
      else: {:error, ErrReg.error!("secrets/invalid_key")}
  end

  def validate_key(_), do: {:error, ErrReg.error!("secrets/invalid_key")}

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
