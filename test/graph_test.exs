defmodule Comn.Repo.Graphs.BehaviourTest do
  use ExUnit.Case, async: true

  test "Comn.Repo.Graphs behaviour defines required callbacks" do
    callbacks = Comn.Repo.Graphs.behaviour_info(:callbacks)
    assert {:graph_create, 1} in callbacks
    assert {:graph_delete, 1} in callbacks
    assert {:graph_info, 1} in callbacks
    assert {:graph_read, 1} in callbacks
    assert {:graph_update, 2} in callbacks
    assert {:query_graph, 2} in callbacks
  end
end

defmodule Comn.Repo.Graphs.GraphTest do
  use ExUnit.Case

  alias Comn.Repo.Graphs.{Graph, GraphStruct}

  setup do
    # Ensure clean agent state for each test
    case Process.whereis(Graph) do
      nil -> :ok
      pid -> Agent.update(pid, fn _ -> %{} end)
    end

    :ok
  end

  describe "create → info → read roundtrip" do
    test "creates a graph and reads it back" do
      assert {:ok, %GraphStruct{id: id, directed?: true}} = Graph.graph_create(name: "test")

      assert {:ok, info} = Graph.graph_info(id)
      assert info.name == "test"
      assert info.directed? == true
      assert info.vertex_count == 0
      assert info.edge_count == 0

      assert {:ok, %GraphStruct{id: ^id, name: "test"}} = Graph.graph_read(id)
    end

    test "creates undirected graph" do
      assert {:ok, %GraphStruct{directed?: false}} =
               Graph.graph_create(name: "undirected", directed?: false)
    end
  end

  describe "vertices and edges" do
    test "add vertices and edges, verify counts" do
      {:ok, %GraphStruct{id: id}} = Graph.graph_create(name: "network")

      {:ok, _} =
        Graph.graph_update(id,
          add_vertices: [:a, :b, :c],
          add_edges: [{:a, :b}, {:b, :c}]
        )

      {:ok, info} = Graph.graph_info(id)
      assert info.vertex_count == 3
      assert info.edge_count == 2
    end

    test "remove vertices and edges" do
      {:ok, %GraphStruct{id: id}} = Graph.graph_create()

      {:ok, _} =
        Graph.graph_update(id,
          add_vertices: [:a, :b, :c],
          add_edges: [{:a, :b}, {:b, :c}]
        )

      {:ok, _} = Graph.graph_update(id, remove_edges: [{:a, :b}])
      {:ok, info} = Graph.graph_info(id)
      assert info.edge_count == 1

      {:ok, _} = Graph.graph_update(id, remove_vertices: [:c])
      {:ok, info} = Graph.graph_info(id)
      assert info.vertex_count == 2
      # removing :c should also remove the :b -> :c edge
      assert info.edge_count == 0
    end
  end

  describe "queries" do
    test "shortest path" do
      {:ok, %GraphStruct{id: id}} = Graph.graph_create()

      Graph.graph_update(id,
        add_vertices: [:a, :b, :c, :d],
        add_edges: [{:a, :b}, {:b, :c}, {:c, :d}, {:a, :d}]
      )

      assert {:ok, [:a, :d]} = Graph.query_graph(id, type: :shortest_path, from: :a, to: :d)
    end

    test "reachability" do
      {:ok, %GraphStruct{id: id}} = Graph.graph_create()

      Graph.graph_update(id,
        add_vertices: [:a, :b, :c, :isolated],
        add_edges: [{:a, :b}, {:b, :c}]
      )

      {:ok, reachable} = Graph.query_graph(id, type: :reachable, from: :a)
      assert :a in reachable
      assert :b in reachable
      assert :c in reachable
      refute :isolated in reachable
    end

    test "neighbors" do
      {:ok, %GraphStruct{id: id}} = Graph.graph_create()

      Graph.graph_update(id,
        add_vertices: [:a, :b, :c],
        add_edges: [{:a, :b}, {:a, :c}]
      )

      {:ok, neighbors} = Graph.query_graph(id, type: :neighbors, vertex: :a)
      assert :b in neighbors
      assert :c in neighbors
    end
  end

  describe "error cases" do
    test "query nonexistent graph" do
      assert {:error, {:not_found, "bogus"}} = Graph.query_graph("bogus", type: :vertices)
    end

    test "delete nonexistent graph" do
      assert {:error, {:not_found, "bogus"}} = Graph.graph_delete("bogus")
    end

    test "info on nonexistent graph" do
      assert {:error, {:not_found, "bogus"}} = Graph.graph_info("bogus")
    end

    test "read nonexistent graph" do
      assert {:error, {:not_found, "bogus"}} = Graph.graph_read("bogus")
    end

    test "unknown query type" do
      {:ok, %GraphStruct{id: id}} = Graph.graph_create()
      assert {:error, {:unknown_query_type, :bogus}} = Graph.query_graph(id, type: :bogus)
    end
  end

  describe "Comn.Repo callbacks" do
    test "describe delegates to graph_info" do
      {:ok, %GraphStruct{id: id}} = Graph.graph_create(name: "repo-test")
      assert {:ok, %{name: "repo-test"}} = Graph.describe(id)
    end

    test "set and get vertex" do
      {:ok, %GraphStruct{id: id}} = Graph.graph_create()
      assert :ok = Graph.set(id, vertex: :x)
      assert {:ok, :x} = Graph.get(id, vertex: :x)
    end

    test "set and get edge" do
      {:ok, %GraphStruct{id: id}} = Graph.graph_create()
      Graph.set(id, vertex: :a)
      Graph.set(id, vertex: :b)
      assert :ok = Graph.set(id, edge: {:a, :b})
      assert {:ok, edge} = Graph.get(id, edge: {:a, :b})
      assert edge.v1 == :a
      assert edge.v2 == :b
    end

    test "delete vertex via Repo" do
      {:ok, %GraphStruct{id: id}} = Graph.graph_create()
      Graph.set(id, vertex: :a)
      assert :ok = Graph.delete(id, vertex: :a)
      assert {:error, {:not_found, :a}} = Graph.get(id, vertex: :a)
    end

    test "observe returns all vertices and edges" do
      {:ok, %GraphStruct{id: id}} = Graph.graph_create()

      Graph.graph_update(id,
        add_vertices: [:a, :b],
        add_edges: [{:a, :b}]
      )

      assert {:ok, %{vertices: vertices, edges: edges}} = Graph.observe(id, [])
      assert :a in vertices
      assert :b in vertices
      assert length(edges) == 1
    end
  end

  describe "graph_delete" do
    test "deletes an existing graph" do
      {:ok, %GraphStruct{id: id}} = Graph.graph_create(name: "deleteme")
      assert :ok = Graph.graph_delete(id)
      assert {:error, {:not_found, ^id}} = Graph.graph_read(id)
    end
  end
end
