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

  @callback describe(term()) :: {:ok, map()} | {:error, term()}
  @callback get(term(), keyword()) :: {:ok, term()} | {:error, term()}
  @callback set(term(), keyword()) :: :ok | {:ok, term()} | {:error, term()}
  @callback delete(term(), keyword()) :: :ok | {:ok, term()} | {:error, term()}
  @callback observe(term(), keyword()) :: Enumerable.t() | {:error, term()}

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
