defmodule Comn.Repo.Graphs.Graph do
  @moduledoc """
  libgraph-backed implementation of `Comn.Repo.Graphs` and `Comn.Repo`.

  Operates directly on `Comn.Repo.Graphs.GraphStruct` — no process, no
  registry. The caller holds the struct, passes it in, gets an updated
  one back. Supports directed and undirected graphs with five traversal
  modes: `:shortest_path`, `:reachable`, `:neighbors`, `:vertices`, `:edges`.

  Implements `@behaviour Comn` for uniform introspection.

  ## Examples

      iex> {:ok, g} = Comn.Repo.Graphs.Graph.create(name: "test")
      iex> g.name
      "test"

      iex> Comn.Repo.Graphs.Graph.look()
      "Graphs.Graph — libgraph-backed directed/undirected graph with traversal"
  """

  alias Comn.Repo.Graphs.GraphStruct
  alias Comn.Errors.Registry, as: ErrReg

  @behaviour Comn
  @behaviour Comn.Repo
  @behaviour Comn.Repo.Graphs

  @doc "Creates a new graph. Opts: `:name`, `:directed?` (default `true`), `:id`, `:metadata`."
  @spec create(keyword()) :: {:ok, Comn.Repo.Graphs.GraphStruct.t()}
  def create(opts \\ []) do
    name = Keyword.get(opts, :name)
    directed? = Keyword.get(opts, :directed?, true)
    id = Keyword.get_lazy(opts, :id, &Comn.Secrets.Local.UUID.uuid4/0)

    graph =
      if directed?,
        do: Graph.new(type: :directed),
        else: Graph.new(type: :undirected)

    {:ok,
     %GraphStruct{
       id: id,
       name: name,
       graph: graph,
       directed?: directed?,
       metadata: Keyword.get(opts, :metadata, %{})
     }}
  end

  # Comn.Repo.Graphs callbacks

  @impl Comn.Repo.Graphs
  def link(%GraphStruct{graph: g} = gs, from, to, opts \\ []) do
    label = Keyword.get(opts, :label)
    weight = Keyword.get(opts, :weight)

    g = Graph.add_vertices(g, [from, to])

    g =
      cond do
        label != nil and weight != nil ->
          Graph.add_edge(g, from, to, label: label, weight: weight)

        label != nil ->
          Graph.add_edge(g, from, to, label: label)

        weight != nil ->
          Graph.add_edge(g, from, to, weight: weight)

        true ->
          Graph.add_edge(g, from, to)
      end

    {:ok, %{gs | graph: g}}
  end

  @impl Comn.Repo.Graphs
  def unlink(%GraphStruct{graph: g} = gs, from, to, _opts \\ []) do
    {:ok, %{gs | graph: Graph.delete_edge(g, from, to)}}
  end

  @impl Comn.Repo.Graphs
  def traverse(%GraphStruct{graph: g}, query) do
    case Keyword.fetch!(query, :type) do
      :shortest_path ->
        from = Keyword.fetch!(query, :from)
        to = Keyword.fetch!(query, :to)
        {:ok, Graph.dijkstra(g, from, to)}

      :reachable ->
        from = Keyword.fetch!(query, :from)
        {:ok, Graph.reachable(g, [from])}

      :neighbors ->
        vertex = Keyword.fetch!(query, :vertex)
        {:ok, Graph.neighbors(g, vertex)}

      :vertices ->
        {:ok, Graph.vertices(g)}

      :edges ->
        {:ok, Graph.edges(g)}

      other ->
        {:error, ErrReg.error!("repo.graph/unknown_query_type", message: "unknown query type: #{inspect(other)}")}
    end
  end

  # Comn.Repo callbacks

  @impl Comn.Repo
  def describe(%GraphStruct{id: id, name: name, directed?: dir, graph: g}) do
    {:ok,
     %{
       id: id,
       name: name,
       directed?: dir,
       vertex_count: Graph.num_vertices(g),
       edge_count: Graph.num_edges(g)
     }}
  end

  @impl Comn.Repo
  def get(%GraphStruct{graph: g}, opts) do
    vertex = Keyword.get(opts, :vertex)

    if vertex != nil do
      if Graph.has_vertex?(g, vertex),
        do: {:ok, vertex},
        else: {:error, ErrReg.error!("repo.table/not_found", field: vertex)}
    else
      {:error, ErrReg.error!("repo.graph/missing_key")}
    end
  end

  @impl Comn.Repo
  def set(%GraphStruct{graph: g} = gs, opts) do
    vertex = Keyword.get(opts, :vertex)

    if vertex != nil do
      {:ok, %{gs | graph: Graph.add_vertex(g, vertex)}}
    else
      {:error, ErrReg.error!("repo.graph/missing_key")}
    end
  end

  @impl Comn.Repo
  def delete(%GraphStruct{graph: g} = gs, opts) do
    vertex = Keyword.get(opts, :vertex)

    if vertex != nil do
      {:ok, %{gs | graph: Graph.delete_vertex(g, vertex)}}
    else
      {:error, ErrReg.error!("repo.graph/missing_key")}
    end
  end

  @impl Comn.Repo
  def observe(%GraphStruct{graph: g}, _opts) do
    {:ok, %{vertices: Graph.vertices(g), edges: Graph.edges(g)}}
  end

  # Comn callbacks

  @impl Comn
  def look, do: "Graphs.Graph — libgraph-backed directed/undirected graph with traversal"

  @impl Comn
  def recon do
    %{
      backend: :libgraph,
      supports: [:directed, :undirected],
      traversal: [:shortest_path, :reachable, :neighbors, :vertices, :edges],
      type: :implementation
    }
  end

  @impl Comn
  def choices do
    %{
      directed?: [true, false],
      traversal: ["shortest_path", "reachable", "neighbors", "vertices", "edges"]
    }
  end

  @impl Comn
  def act(%{action: :create} = input) do
    create(Map.to_list(Map.delete(input, :action)))
  end

  def act(%{action: :traverse, graph: graph, query: query}) do
    traverse(graph, query)
  end

  def act(%{action: :link, graph: graph, from: from, to: to} = input) do
    link(graph, from, to, Map.to_list(Map.drop(input, [:action, :graph, :from, :to])))
  end

  def act(_input), do: {:error, :unknown_action}
end
