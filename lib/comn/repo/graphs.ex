defmodule Comn.Repo.Graphs do
  @moduledoc """
  Behaviour for graph repository operations.

  Extends `Comn.Repo` with what's structurally unique to graphs: `link`,
  `unlink`, and `traverse`. Node CRUD is handled by the base `Comn.Repo`
  callbacks (`get`/`set`/`delete`). Backed by `Comn.Repo.Graphs.Graph`
  (libgraph).

  Also implements `@behaviour Comn` for uniform introspection.

  ## Examples

      iex> Comn.Repo.Graphs.look()
      "Graphs — link, unlink, and traverse nodes and edges"

      iex> %{traverse_types: types} = Comn.Repo.Graphs.recon()
      iex> :shortest_path in types
      true
  """

  @behaviour Comn

  alias Comn.Repo.Graphs.GraphStruct

  @callback link(graph :: GraphStruct.t(), from :: term(), to :: term(), opts :: keyword()) ::
              {:ok, GraphStruct.t()} | {:error, term()}

  @callback unlink(graph :: GraphStruct.t(), from :: term(), to :: term(), opts :: keyword()) ::
              {:ok, GraphStruct.t()} | {:error, term()}

  @callback traverse(graph :: GraphStruct.t(), query :: keyword()) ::
              {:ok, term()} | {:error, term()}

  @impl Comn
  def look, do: "Graphs — link, unlink, and traverse nodes and edges"

  @impl Comn
  def recon do
    %{
      callbacks: [:link, :unlink, :traverse],
      extends: Comn.Repo,
      traverse_types: [:shortest_path, :reachable, :neighbors, :vertices, :edges],
      type: :behaviour
    }
  end

  @impl Comn
  def choices do
    %{
      implementations: ["Graph"],
      traversal: ["shortest_path", "reachable", "neighbors", "vertices", "edges"]
    }
  end

  @impl Comn
  def act(_input), do: {:error, :behaviour_only}
end
