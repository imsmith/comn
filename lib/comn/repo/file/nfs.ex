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
  alias Comn.Errors.Registry, as: ErrReg

  @behaviour Comn
  @behaviour Comn.Repo
  @behaviour Comn.Repo.File

  # Comn.Repo.File callbacks

  @spec open(term(), keyword()) :: {:ok, Comn.Repo.File.handle()} | {:error, term()}
  @impl Comn.Repo.File
  def open(path, opts \\ []) do
    mount = Keyword.fetch!(opts, :mount)
    full_path = resolve_path(mount, path)

    case Local.open(full_path, Keyword.delete(opts, :mount)) do
      {:ok, fs} ->
        {:ok, %{fs | backend: __MODULE__, metadata: Map.put(fs.metadata, :mount, mount)}}

      {:error, :estale} ->
        {:error, ErrReg.error!("repo.file/stale_handle", field: full_path)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec load(Comn.Repo.File.handle(), keyword()) :: {:ok, Comn.Repo.File.handle()} | {:error, term()}
  @impl Comn.Repo.File
  def load(%FileStruct{backend: __MODULE__} = fs, opts \\ []) do
    case Local.load(fs, opts) do
      {:error, :estale} -> {:error, ErrReg.error!("repo.file/stale_handle", field: fs.path)}
      result -> result
    end
  end

  @spec stream(Comn.Repo.File.handle(), keyword()) :: {:ok, Enumerable.t()} | {:error, term()}
  @impl Comn.Repo.File
  def stream(%FileStruct{backend: __MODULE__} = fs, opts \\ []), do: Local.stream(fs, opts)

  @spec cast(Comn.Repo.File.handle(), keyword()) :: :ok | {:error, term()}
  @impl Comn.Repo.File
  def cast(%FileStruct{backend: __MODULE__} = fs, opts \\ []), do: Local.cast(fs, opts)

  @spec read(Comn.Repo.File.handle(), keyword()) :: {:ok, binary()} | {:error, term()}
  @impl Comn.Repo.File
  def read(%FileStruct{backend: __MODULE__} = fs, opts \\ []), do: Local.read(fs, opts)

  @spec write(Comn.Repo.File.handle(), iodata(), keyword()) :: {:ok, Comn.Repo.File.handle()} | {:error, term()}
  @impl Comn.Repo.File
  def write(%FileStruct{backend: __MODULE__} = fs, data, opts \\ []),
    do: Local.write(fs, data, opts)

  @spec close(Comn.Repo.File.handle(), keyword()) :: :ok | {:error, term()}
  @impl Comn.Repo.File
  def close(%FileStruct{backend: __MODULE__} = fs, opts \\ []), do: Local.close(fs, opts)

  # Comn.Repo callbacks — delegate to Local

  @spec describe(Comn.Repo.resource()) :: {:ok, map()} | {:error, term()}
  @impl Comn.Repo
  def describe(fs), do: Local.describe(fs)

  @spec get(Comn.Repo.resource(), keyword()) :: {:ok, term()} | {:error, term()}
  @impl Comn.Repo
  def get(fs, opts), do: Local.get(fs, opts)

  @spec set(Comn.Repo.resource(), keyword()) :: :ok | {:ok, term()} | {:error, term()}
  @impl Comn.Repo
  def set(fs, opts), do: Local.set(fs, opts)

  @spec delete(Comn.Repo.resource(), keyword()) :: :ok | {:ok, term()} | {:error, term()}
  @impl Comn.Repo
  def delete(fs, opts), do: Local.delete(fs, opts)

  @spec observe(Comn.Repo.resource(), keyword()) :: Enumerable.t() | {:error, term()}
  @impl Comn.Repo
  def observe(fs, opts), do: Local.observe(fs, opts)

  # Comn callbacks

  @spec look() :: String.t()
  @impl Comn
  def look, do: "File.NFS — NFS mount-point file backend with ESTALE detection"

  @spec recon() :: map()
  @impl Comn
  def recon do
    %{
      backend: :nfs,
      delegates_to: Comn.Repo.File.Local,
      requires: [:mount],
      type: :implementation
    }
  end

  @spec choices() :: map()
  @impl Comn
  def choices do
    %{mount: "required — NFS mount point path"}
  end

  @spec act(map()) :: {:ok, term()} | {:error, term()}
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
