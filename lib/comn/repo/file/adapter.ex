defmodule Comn.Repo.File.Adapter do
  @moduledoc false
  # One backend contract over the three public Comn.Repo.File implementations.
  # `open/2` picks the implementation from the :backend option the facade
  # leaves in opts; after that the FileStruct's own :backend field dispatches.

  @behaviour Comn.Repo.File.Backend

  alias Comn.Repo.File.{FileStruct, IPFS, Local, NFS}

  @impls %{local: Local, nfs: NFS, ipfs: IPFS}

  @impl true
  def open(path, opts) do
    {key, opts} = Keyword.pop(opts, :backend, :local)
    Map.fetch!(@impls, key).open(path, opts)
  end

  @impl true
  def close(%FileStruct{state: state, backend: impl} = fs) when state in [:open, :loaded] do
    _ = impl.close(fs, [])
    :ok
  end

  def close(%FileStruct{}), do: :ok

  @impl true
  def drop(%FileStruct{backend: impl} = fs) do
    _ = close(fs)
    _ = impl.delete(fs, [])
    :ok
  end

  @impl true
  def load(%FileStruct{backend: impl} = fs, opts), do: impl.load(fs, opts)
  @impl true
  def stream(%FileStruct{backend: impl} = fs, opts), do: impl.stream(fs, opts)
  @impl true
  def cast(%FileStruct{backend: impl} = fs, opts), do: impl.cast(fs, opts)
  @impl true
  def read(%FileStruct{backend: impl} = fs, opts), do: impl.read(fs, opts)
  @impl true
  def write(%FileStruct{backend: impl} = fs, data, opts), do: impl.write(fs, data, opts)
  @impl true
  def describe(%FileStruct{backend: impl} = fs), do: impl.describe(fs)
  @impl true
  def get(%FileStruct{backend: impl} = fs, opts), do: impl.get(fs, opts)
  @impl true
  def set(%FileStruct{backend: impl} = fs, opts), do: impl.set(fs, opts)
  @impl true
  def delete(%FileStruct{backend: impl} = fs, opts), do: impl.delete(fs, opts)
  @impl true
  def observe(%FileStruct{backend: impl} = fs, opts), do: impl.observe(fs, opts)
end
