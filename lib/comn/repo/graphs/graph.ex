defmodule Comn.Repo.Graphs.Graph do
  @moduledoc """
  libgraph-backed implementation of `Comn.Repo.Graphs` and `Comn.Repo`.

  Operates directly on `Comn.Repo.Graphs.GraphStruct` — no process, no
  registry. The caller holds the struct, passes it in, gets an updated
  one back. Supports directed and undirected graphs with five traversal
  modes: `:shortest_path`, `:reachable`, `:neighbors`, `:vertices`, `:edges`.

  Implements `@behaviour Comn` for uniform introspection.

  ## Spatial use

  Graphs implement the optional spatial callbacks on `Comn.Repo`
  (`enter/2`, `exit/2`, `discover/2`) plus a graph-specific
  `traverse/4`. A `Comn.Zone`'s `:locale` is matched against vertex
  names — strings match string-named vertices; if a same-named atom
  vertex exists, that's matched instead. Errors come back as registered
  codes: `repo.graph/zone_not_found` and `repo.graph/unreachable`.

  ## Examples

      iex> {:ok, g} = Comn.Repo.Graphs.Graph.create(name: "test")
      iex> g.name
      "test"

      iex> Comn.Repo.Graphs.Graph.look()
      "Graphs.Graph — libgraph-backed directed/undirected graph with traversal"
  """

  alias Comn.Repo.Graphs.GraphStruct
  alias Comn.Errors.Registry, as: ErrReg
  alias Comn.Zone

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

  # Spatial (Comn.Repo optional callbacks)

  @doc """
  Positions into a zone within this graph.

  The zone's `:locale` must correspond to an existing vertex — matched
  as a literal string vertex first, falling back to the same-named atom
  via `String.to_existing_atom/1` if no string vertex matches.

  Returns `{:ok, vertex}` with the resolved vertex term, or
  `{:error, ErrorStruct}` with code `repo.graph/zone_not_found` if the
  locale doesn't resolve.

  ## Examples

      iex> {:ok, g} = Comn.Repo.Graphs.Graph.create()
      iex> {:ok, g} = Comn.Repo.Graphs.Graph.link(g, :room_a, :room_b)
      iex> zone = Comn.Zone.new(realm: :local, locale: "room_a")
      iex> Comn.Repo.Graphs.Graph.enter(g, zone)
      {:ok, :room_a}
  """
  @impl Comn.Repo
  @spec enter(GraphStruct.t(), Zone.t()) :: {:ok, term()} | {:error, term()}
  def enter(%GraphStruct{graph: g}, %Zone{} = zone) do
    case zone_to_vertex(g, zone) do
      {:ok, vertex} -> {:ok, vertex}
      :error -> {:error, ErrReg.error!("repo.graph/zone_not_found", field: zone.locale)}
    end
  end

  @doc """
  Clears any positional state for a zone.

  Currently a no-op — the `Graph` impl holds no per-caller state, so
  there's nothing to clear. Defined to satisfy the optional callback
  contract; future stateful backends may track per-zone cursors here.
  """
  @impl Comn.Repo
  @spec exit(GraphStruct.t(), Zone.t()) :: :ok
  def exit(%GraphStruct{}, %Zone{}), do: :ok

  @doc """
  Returns vertices reachable in one hop from the zone's locale.

  Adjacency uses `Graph.neighbors/2` — for directed graphs, this is the
  out-neighbours; for undirected graphs, both sides. Errors with
  `repo.graph/zone_not_found` if the zone doesn't resolve to a vertex.

  ## Examples

      iex> {:ok, g} = Comn.Repo.Graphs.Graph.create()
      iex> {:ok, g} = Comn.Repo.Graphs.Graph.link(g, :hub, :a)
      iex> {:ok, g} = Comn.Repo.Graphs.Graph.link(g, :hub, :b)
      iex> zone = Comn.Zone.new(realm: :local, locale: "hub")
      iex> {:ok, neighbors} = Comn.Repo.Graphs.Graph.discover(g, zone)
      iex> Enum.sort(neighbors)
      [:a, :b]
  """
  @impl Comn.Repo
  @spec discover(GraphStruct.t(), Zone.t()) :: {:ok, list()} | {:error, term()}
  def discover(%GraphStruct{graph: g}, %Zone{} = zone) do
    case zone_to_vertex(g, zone) do
      {:ok, vertex} -> {:ok, Graph.neighbors(g, vertex)}
      :error -> {:error, ErrReg.error!("repo.graph/zone_not_found", field: zone.locale)}
    end
  end

  @doc """
  Spatial navigation: walk from a source zone to a destination vertex.

  Resolves the `from` zone to a vertex (`zone_to_vertex/2`), runs
  Dijkstra's algorithm to `to`, and returns the destination as a new
  zone (cloning `from` and replacing the `:locale` with the destination
  vertex's locale string) plus the full path.

  Side effect: if the calling process has a `Comn.Contexts` set, the
  context's `:zone` is updated to the destination. This makes traverse
  the canonical "I moved" operation in spatial code.

  Errors:
  - `repo.graph/zone_not_found` — `from` doesn't resolve to a vertex
  - `repo.graph/unreachable` — no path from `from` to `to`

  ## Examples

      iex> {:ok, g} = Comn.Repo.Graphs.Graph.create()
      iex> {:ok, g} = Comn.Repo.Graphs.Graph.link(g, :a, :b)
      iex> {:ok, g} = Comn.Repo.Graphs.Graph.link(g, :b, :c)
      iex> from = Comn.Zone.new(realm: :local, locale: "a")
      iex> {:ok, dest, path} = Comn.Repo.Graphs.Graph.traverse(g, from, :c, [])
      iex> {dest.locale, path}
      {"c", [:a, :b, :c]}
  """
  @spec traverse(GraphStruct.t(), Zone.t(), term(), keyword()) ::
          {:ok, Zone.t(), [term()]} | {:error, term()}
  def traverse(%GraphStruct{graph: g}, %Zone{} = from, to, _opts) do
    with {:ok, from_vertex} <- zone_to_vertex(g, from),
         path when is_list(path) <- Graph.dijkstra(g, from_vertex, to) do
      dest = %Zone{from | locale: vertex_to_locale(to)}
      maybe_update_context_zone(dest)
      {:ok, dest, path}
    else
      :error ->
        {:error, ErrReg.error!("repo.graph/zone_not_found", field: from.locale)}

      nil ->
        {:error, ErrReg.error!("repo.graph/unreachable", field: to)}
    end
  end

  defp zone_to_vertex(_g, %Zone{locale: nil}), do: :error

  defp zone_to_vertex(g, %Zone{locale: locale}) do
    cond do
      Graph.has_vertex?(g, locale) ->
        {:ok, locale}

      is_binary(locale) ->
        try do
          atom = String.to_existing_atom(locale)
          if Graph.has_vertex?(g, atom), do: {:ok, atom}, else: :error
        rescue
          ArgumentError -> :error
        end

      true ->
        :error
    end
  end

  defp vertex_to_locale(v) when is_binary(v), do: v
  defp vertex_to_locale(v) when is_atom(v), do: Atom.to_string(v)
  defp vertex_to_locale(v), do: inspect(v)

  defp maybe_update_context_zone(%Zone{} = zone) do
    if Comn.Contexts.get(), do: Comn.Contexts.put(:zone, zone), else: :ok
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
