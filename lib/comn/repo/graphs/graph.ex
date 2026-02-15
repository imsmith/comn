defmodule Comn.Repo.Graphs.Graph do
  @moduledoc """
  libgraph-backed implementation of Comn.Repo.Graphs and Comn.Repo.

  Uses an Agent to store graphs by ID. Start the agent with `start_link/0`
  or let it be started on first use via `ensure_started/0`.
  """

  alias Comn.Repo.Graphs.GraphStruct

  @behaviour Comn.Repo
  @behaviour Comn.Repo.Graphs

  @agent __MODULE__

  def start_link(opts \\ []) do
    Agent.start_link(fn -> %{} end, Keyword.put_new(opts, :name, @agent))
  end

  defp ensure_started do
    case Process.whereis(@agent) do
      nil -> start_link()
      _pid -> :ok
    end
  end

  # Comn.Repo.Graphs callbacks

  @impl Comn.Repo.Graphs
  def graph_create(opts \\ []) do
    ensure_started()
    name = Keyword.get(opts, :name)
    directed? = Keyword.get(opts, :directed?, true)

    graph =
      if directed?,
        do: Graph.new(type: :directed),
        else: Graph.new(type: :undirected)

    id = generate_id()

    gs = %GraphStruct{
      id: id,
      name: name,
      graph: graph,
      directed?: directed?,
      metadata: Keyword.get(opts, :metadata, %{})
    }

    Agent.update(@agent, &Map.put(&1, id, gs))
    {:ok, gs}
  end

  @impl Comn.Repo.Graphs
  def graph_delete(id) do
    ensure_started()

    case Agent.get(@agent, &Map.get(&1, id)) do
      nil -> {:error, {:not_found, id}}
      _gs ->
        Agent.update(@agent, &Map.delete(&1, id))
        :ok
    end
  end

  @impl Comn.Repo.Graphs
  def graph_info(id) do
    ensure_started()

    case Agent.get(@agent, &Map.get(&1, id)) do
      nil ->
        {:error, {:not_found, id}}

      %GraphStruct{graph: g, name: name, directed?: dir} ->
        {:ok,
         %{
           id: id,
           name: name,
           directed?: dir,
           vertex_count: Graph.num_vertices(g),
           edge_count: Graph.num_edges(g)
         }}
    end
  end

  @impl Comn.Repo.Graphs
  def graph_read(id) do
    ensure_started()

    case Agent.get(@agent, &Map.get(&1, id)) do
      nil -> {:error, {:not_found, id}}
      gs -> {:ok, gs}
    end
  end

  @impl Comn.Repo.Graphs
  def graph_update(id, updates) do
    ensure_started()

    case Agent.get(@agent, &Map.get(&1, id)) do
      nil ->
        {:error, {:not_found, id}}

      %GraphStruct{graph: g} = gs ->
        g = apply_updates(g, updates)
        updated = %{gs | graph: g}
        Agent.update(@agent, &Map.put(&1, id, updated))
        {:ok, updated}
    end
  end

  @impl Comn.Repo.Graphs
  def query_graph(id, query) do
    ensure_started()

    case Agent.get(@agent, &Map.get(&1, id)) do
      nil ->
        {:error, {:not_found, id}}

      %GraphStruct{graph: g} ->
        execute_query(g, query)
    end
  end

  # Comn.Repo callbacks

  @impl Comn.Repo
  def describe(id) do
    graph_info(id)
  end

  @impl Comn.Repo
  def get(id, opts) do
    ensure_started()

    case Agent.get(@agent, &Map.get(&1, id)) do
      nil ->
        {:error, {:not_found, id}}

      %GraphStruct{graph: g} ->
        vertex = Keyword.get(opts, :vertex)
        edge = Keyword.get(opts, :edge)

        cond do
          vertex != nil ->
            if Graph.has_vertex?(g, vertex),
              do: {:ok, vertex},
              else: {:error, {:not_found, vertex}}

          edge != nil ->
            {v1, v2} = edge

            if Graph.edge(g, v1, v2) != nil,
              do: {:ok, Graph.edge(g, v1, v2)},
              else: {:error, {:not_found, edge}}

          true ->
            {:error, :missing_key}
        end
    end
  end

  @impl Comn.Repo
  def set(id, opts) do
    ensure_started()

    case Agent.get(@agent, &Map.get(&1, id)) do
      nil ->
        {:error, {:not_found, id}}

      %GraphStruct{graph: g} = gs ->
        vertex = Keyword.get(opts, :vertex)
        edge = Keyword.get(opts, :edge)

        g =
          cond do
            vertex != nil -> Graph.add_vertex(g, vertex)
            edge != nil -> {v1, v2} = edge; Graph.add_edge(g, v1, v2)
            true -> g
          end

        updated = %{gs | graph: g}
        Agent.update(@agent, &Map.put(&1, id, updated))
        :ok
    end
  end

  @impl Comn.Repo
  def delete(id, opts) do
    ensure_started()

    case Agent.get(@agent, &Map.get(&1, id)) do
      nil ->
        {:error, {:not_found, id}}

      %GraphStruct{graph: g} = gs ->
        vertex = Keyword.get(opts, :vertex)
        edge = Keyword.get(opts, :edge)

        g =
          cond do
            vertex != nil -> Graph.delete_vertex(g, vertex)
            edge != nil -> {v1, v2} = edge; Graph.delete_edge(g, v1, v2)
            true -> g
          end

        updated = %{gs | graph: g}
        Agent.update(@agent, &Map.put(&1, id, updated))
        :ok
    end
  end

  @impl Comn.Repo
  def observe(id, _opts) do
    ensure_started()

    case Agent.get(@agent, &Map.get(&1, id)) do
      nil ->
        {:error, {:not_found, id}}

      %GraphStruct{graph: g} ->
        vertices = Graph.vertices(g)
        edges = Graph.edges(g)
        {:ok, %{vertices: vertices, edges: edges}}
    end
  end

  # Internal helpers

  defp generate_id do
    <<a::32, b::16, c::16, d::16, e::48>> = :crypto.strong_rand_bytes(16)

    "#{Integer.to_string(a, 16)}-#{Integer.to_string(b, 16)}-#{Integer.to_string(c, 16)}-#{Integer.to_string(d, 16)}-#{Integer.to_string(e, 16)}"
    |> String.downcase()
  end

  defp apply_updates(graph, updates) do
    graph
    |> apply_add_vertices(Keyword.get(updates, :add_vertices, []))
    |> apply_add_edges(Keyword.get(updates, :add_edges, []))
    |> apply_remove_vertices(Keyword.get(updates, :remove_vertices, []))
    |> apply_remove_edges(Keyword.get(updates, :remove_edges, []))
  end

  defp apply_add_vertices(g, vertices), do: Enum.reduce(vertices, g, &Graph.add_vertex(&2, &1))
  defp apply_add_edges(g, edges), do: Enum.reduce(edges, g, fn {v1, v2}, g -> Graph.add_edge(g, v1, v2) end)
  defp apply_remove_vertices(g, vertices), do: Enum.reduce(vertices, g, &Graph.delete_vertex(&2, &1))
  defp apply_remove_edges(g, edges), do: Enum.reduce(edges, g, fn {v1, v2}, g -> Graph.delete_edge(g, v1, v2) end)

  defp execute_query(graph, query) do
    case Keyword.fetch!(query, :type) do
      :shortest_path ->
        from = Keyword.fetch!(query, :from)
        to = Keyword.fetch!(query, :to)

        case Graph.dijkstra(graph, from, to) do
          nil -> {:ok, nil}
          path -> {:ok, path}
        end

      :reachable ->
        from = Keyword.fetch!(query, :from)
        reachable = Graph.reachable(graph, [from])
        {:ok, reachable}

      :vertices ->
        {:ok, Graph.vertices(graph)}

      :edges ->
        {:ok, Graph.edges(graph)}

      :neighbors ->
        vertex = Keyword.fetch!(query, :vertex)
        {:ok, Graph.neighbors(graph, vertex)}

      other ->
        {:error, {:unknown_query_type, other}}
    end
  end
end
