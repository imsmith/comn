defmodule Comn.Repo do
  @moduledoc """
  Common I/O behaviour for data repositories.

  Defines the five verbs every repo must support — `describe`, `get`, `set`,
  `delete`, `observe` — regardless of whether the backend is a table, file,
  graph, or shell command. Extension behaviours (`Comn.Repo.Table`,
  `Comn.Repo.File`, `Comn.Repo.Graphs`, `Comn.Repo.Cmd`) add domain-specific
  callbacks on top of these.

  Also implements `@behaviour Comn` for uniform introspection.

  ## Examples

      iex> Comn.Repo.look()
      "Repo — common I/O behaviour for data repositories (tables, files, graphs, commands)"

      iex> %{extensions: exts} = Comn.Repo.recon()
      iex> Comn.Repo.Table in exts
      true
  """

  @behaviour Comn

  @typedoc "The resource being operated on — a table name, file handle, graph struct, etc."
  @type resource :: term()

  @doc """
  Returns metadata about the resource (table info, file stat, graph summary).

  Errors: `repo.table/not_found`, `repo.file/invalid_state`.
  """
  @callback describe(resource()) :: {:ok, map()} | {:error, term()}

  @doc """
  Retrieves a value. Opts specify the key or query.

  Errors: `{:not_found, key}`, `repo.file/invalid_state`, `repo.graph/missing_key`.
  """
  @callback get(resource(), keyword()) :: {:ok, term()} | {:error, term()}

  @doc """
  Stores a value. Opts must include `:key` and `:value` (or backend equivalent).

  Errors: `repo.table/not_found`, `repo.file/invalid_state`, `repo.graph/missing_key`.
  """
  @callback set(resource(), keyword()) :: :ok | {:ok, term()} | {:error, term()}

  @doc """
  Removes a value. Opts must include `:key` (or backend equivalent).

  Errors: `repo.table/not_found`, `repo.graph/missing_key`.
  """
  @callback delete(resource(), keyword()) :: :ok | {:ok, term()} | {:error, term()}

  @doc """
  Returns a stream or snapshot of the resource's contents.

  Errors: `repo.table/not_found`, `repo.file/invalid_state`.
  """
  @callback observe(resource(), keyword()) :: Enumerable.t() | {:error, term()}

  @doc """
  Spatial: position into a zone within this repo.

  Optional. Spatial repos (graphs, presence-aware stores) implement; flat
  repos (ETS tables, blob stores) do not. Returns `{:ok, position}` where
  position is repo-defined context, or `{:error, _}` if the zone is not
  reachable in this repo.
  """
  @callback enter(resource(), Comn.Zone.t()) :: {:ok, term()} | {:error, term()}

  @doc "Spatial: clear positional state for a zone. Optional."
  @callback exit(resource(), Comn.Zone.t()) :: :ok | {:error, term()}

  @doc """
  Spatial: list zones reachable from the given zone.

  Optional. Returns `{:ok, [zone_or_locator]}` for spatial repos.
  """
  @callback discover(resource(), Comn.Zone.t()) :: {:ok, list()} | {:error, term()}

  @optional_callbacks enter: 2, exit: 2, discover: 2

  @impl Comn
  def look, do: "Repo — common I/O behaviour for data repositories (tables, files, graphs, commands)"

  @impl Comn
  def recon do
    %{
      callbacks: [:describe, :get, :set, :delete, :observe],
      extensions: [Comn.Repo.Table, Comn.Repo.File, Comn.Repo.Graphs, Comn.Repo.Cmd],
      type: :behaviour
    }
  end

  @impl Comn
  def choices do
    %{
      extensions: ["Table", "File", "Graphs", "Cmd"],
      implementations: ["Table.ETS", "File.Local", "File.NFS", "File.IPFS", "Graphs.Graph", "Cmd.Shell"]
    }
  end

  @impl Comn
  def act(_input), do: {:error, :behaviour_only}
end
