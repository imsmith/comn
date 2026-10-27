defmodule Comn.Repo.Graphs.BehaviourTest do
  use ExUnit.Case, async: true

  alias Comn.Repo.Graphs

  test "Comn.Repo.Graphs behaviour defines link/unlink/traverse" do
    callbacks = Graphs.behaviour_info(:callbacks)
    assert {:link, 4} in callbacks
    assert {:unlink, 4} in callbacks
    assert {:traverse, 2} in callbacks
  end
end

defmodule Comn.Repo.Graphs.GraphTest do
  use ExUnit.Case, async: true

  alias Comn.Errors.ErrorStruct
  alias Comn.Repo.Graphs.{Graph, GraphStruct}

  describe "create" do
    test "creates a directed graph by default" do
      assert {:ok, %GraphStruct{directed?: true, name: "test"}} = Graph.create(name: "test")
    end

    test "creates undirected graph" do
      assert {:ok, %GraphStruct{directed?: false}} = Graph.create(directed?: false)
    end

    test "generates a uuid when no id given" do
      {:ok, %GraphStruct{id: id}} = Graph.create()
      assert is_binary(id)
      assert String.contains?(id, "-")
    end

    test "accepts a caller-supplied id" do
      assert {:ok, %GraphStruct{id: "my-id"}} = Graph.create(id: "my-id")
    end
  end

  describe "link and unlink" do
    test "link adds an edge between nodes" do
      {:ok, gs0} = Graph.create()
      {:ok, gs} = Graph.link(gs0, :a, :b)

      {:ok, info} = Graph.describe(gs)
      assert info.vertex_count == 2
      assert info.edge_count == 1
    end

    test "link with label and weight" do
      {:ok, gs0} = Graph.create()
      {:ok, gs} = Graph.link(gs0, :a, :b, label: "knows", weight: 5)

      {:ok, edges} = Graph.traverse(gs, type: :edges)
      [edge] = edges
      assert edge.v1 == :a
      assert edge.v2 == :b
      assert edge.label == "knows"
      assert edge.weight == 5
    end

    test "unlink removes an edge" do
      {:ok, gs0} = Graph.create()
      {:ok, gs1} = Graph.link(gs0, :a, :b)
      {:ok, gs2} = Graph.link(gs1, :b, :c)
      {:ok, gs} = Graph.unlink(gs2, :a, :b)

      {:ok, info} = Graph.describe(gs)
      assert info.edge_count == 1
      # nodes remain
      assert info.vertex_count == 3
    end
  end

  describe "traverse" do
    test "shortest path" do
      {:ok, gs0} = Graph.create()
      {:ok, gs1} = Graph.link(gs0, :a, :b)
      {:ok, gs2} = Graph.link(gs1, :b, :c)
      {:ok, gs3} = Graph.link(gs2, :c, :d)
      {:ok, gs} = Graph.link(gs3, :a, :d)

      assert {:ok, [:a, :d]} = Graph.traverse(gs, type: :shortest_path, from: :a, to: :d)
    end

    test "reachability" do
      {:ok, gs0} = Graph.create()
      {:ok, gs1} = Graph.link(gs0, :a, :b)
      {:ok, gs2} = Graph.link(gs1, :b, :c)
      {:ok, gs} = Graph.set(gs2, vertex: :isolated)

      {:ok, reachable} = Graph.traverse(gs, type: :reachable, from: :a)
      assert :a in reachable
      assert :b in reachable
      assert :c in reachable
      refute :isolated in reachable
    end

    test "neighbors" do
      {:ok, gs0} = Graph.create()
      {:ok, gs1} = Graph.link(gs0, :a, :b)
      {:ok, gs} = Graph.link(gs1, :a, :c)

      {:ok, neighbors} = Graph.traverse(gs, type: :neighbors, vertex: :a)
      assert :b in neighbors
      assert :c in neighbors
    end

    test "unknown query type returns error" do
      {:ok, gs} = Graph.create()

      assert {:error, %ErrorStruct{code: "repo.graph/unknown_query_type"}} =
               Graph.traverse(gs, type: :bogus)
    end
  end

  describe "Repo callbacks" do
    test "describe returns graph metadata" do
      {:ok, gs0} = Graph.create(name: "repo-test")
      {:ok, gs} = Graph.link(gs0, :x, :y)

      assert {:ok, info} = Graph.describe(gs)
      assert info.name == "repo-test"
      assert info.vertex_count == 2
      assert info.edge_count == 1
    end

    test "set and get vertex" do
      {:ok, gs0} = Graph.create()
      {:ok, gs} = Graph.set(gs0, vertex: :x)
      assert {:ok, :x} = Graph.get(gs, vertex: :x)
    end

    test "get missing vertex returns error" do
      {:ok, gs} = Graph.create()
      assert {:error, %ErrorStruct{code: "repo.table/not_found"}} = Graph.get(gs, vertex: :x)
    end

    test "delete vertex" do
      {:ok, gs0} = Graph.create()
      {:ok, gs1} = Graph.set(gs0, vertex: :a)
      {:ok, gs} = Graph.delete(gs1, vertex: :a)
      assert {:error, %ErrorStruct{code: "repo.table/not_found"}} = Graph.get(gs, vertex: :a)
    end

    test "delete vertex removes its edges" do
      {:ok, gs0} = Graph.create()
      {:ok, gs1} = Graph.link(gs0, :a, :b)
      {:ok, gs} = Graph.delete(gs1, vertex: :a)

      {:ok, info} = Graph.describe(gs)
      assert info.vertex_count == 1
      assert info.edge_count == 0
    end

    test "observe returns all vertices and edges" do
      {:ok, gs0} = Graph.create()
      {:ok, gs} = Graph.link(gs0, :a, :b)

      assert {:ok, %{vertices: vertices, edges: edges}} = Graph.observe(gs, [])
      assert :a in vertices
      assert :b in vertices
      assert length(edges) == 1
    end
  end
end
