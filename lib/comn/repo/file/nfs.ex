defmodule Comn.Repo.File.NFS do
  @moduledoc """
  NFS mount-point file backend.

  Wraps `Comn.Repo.File.Local` with path resolution relative to a
  configured mount point and ESTALE (stale NFS handle) detection.
  Requires a `:mount` option on `open/2`.

  Implements `@behaviour Comn` for uniform introspection.

  ## Examples

      iex> Comn.Repo.File.NFS.look()
      "File.NFS — NFS mount-point file backend with ESTALE detection"

      iex> %{delegates_to: Comn.Repo.File.Local} = Comn.Repo.File.NFS.recon()
  """

  alias Comn.Repo.File.{Local, FileStruct}

  @behaviour Comn
  @behaviour Comn.Repo
  @behaviour Comn.Repo.File

  # Comn.Repo.File callbacks

  @impl Comn.Repo.File
  def open(path, opts \\ []) do
    mount = Keyword.fetch!(opts, :mount)
    full_path = resolve_path(mount, path)

    case Local.open(full_path, Keyword.delete(opts, :mount)) do
      {:ok, fs} ->
        {:ok, %{fs | backend: __MODULE__, metadata: Map.put(fs.metadata, :mount, mount)}}

      {:error, :estale} ->
        {:error, {:stale_handle, full_path}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl Comn.Repo.File
  def load(%FileStruct{backend: __MODULE__} = fs, opts \\ []) do
    case Local.load(fs, opts) do
      {:error, :estale} -> {:error, {:stale_handle, fs.path}}
      result -> result
    end
  end

  @impl Comn.Repo.File
  def stream(%FileStruct{backend: __MODULE__} = fs, opts \\ []), do: Local.stream(fs, opts)

  @impl Comn.Repo.File
  def cast(%FileStruct{backend: __MODULE__} = fs, opts \\ []), do: Local.cast(fs, opts)

  @impl Comn.Repo.File
  def read(%FileStruct{backend: __MODULE__} = fs, opts \\ []), do: Local.read(fs, opts)

  @impl Comn.Repo.File
  def write(%FileStruct{backend: __MODULE__} = fs, data, opts \\ []),
    do: Local.write(fs, data, opts)

  @impl Comn.Repo.File
  def close(%FileStruct{backend: __MODULE__} = fs, opts \\ []), do: Local.close(fs, opts)

  # Comn.Repo callbacks — delegate to Local

  @impl Comn.Repo
  def describe(fs), do: Local.describe(fs)

  @impl Comn.Repo
  def get(fs, opts), do: Local.get(fs, opts)

  @impl Comn.Repo
  def set(fs, opts), do: Local.set(fs, opts)

  @impl Comn.Repo
  def delete(fs, opts), do: Local.delete(fs, opts)

  @impl Comn.Repo
  def observe(fs, opts), do: Local.observe(fs, opts)

  # Comn callbacks

  @impl Comn
  def look, do: "File.NFS — NFS mount-point file backend with ESTALE detection"

  @impl Comn
  def recon do
    %{
      backend: :nfs,
      delegates_to: Comn.Repo.File.Local,
      requires: [:mount],
      type: :implementation
    }
  end

  @impl Comn
  def choices do
    %{mount: "required — NFS mount point path"}
  end

  @impl Comn
  def act(%{action: :read, path: path, mount: mount}) do
    with {:ok, fs} <- open(path, mount: mount),
         {:ok, fs} <- load(fs),
         {:ok, data} <- read(fs) do
      close(fs)
      {:ok, data}
    end
  end

  def act(_input), do: {:error, :unknown_action}

  # Helpers

  defp resolve_path(mount, path) do
    Path.join(mount, path)
  end
end
