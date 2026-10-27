defmodule Comn.Repo.Graphs.GraphAdapter do
  @moduledoc false
  # Backend contract over the public Comn.Repo.Graphs.Graph module. State is
  # the GraphStruct value; close and drop have nothing to release.

  @behaviour Comn.Repo.Graphs.Backend

  alias Comn.Repo.Graphs.Graph

  @impl true
  def open(name, opts), do: Graph.create(Keyword.put(opts, :name, name))

  @impl true
  def close(_gs), do: :ok

  @impl true
  def drop(_gs), do: :ok

  @impl true
  defdelegate link(gs, from, to, opts), to: Graph
  @impl true
  defdelegate unlink(gs, from, to, opts), to: Graph
  @impl true
  defdelegate traverse(gs, query), to: Graph
  @impl true
  defdelegate traverse(gs, from, to, opts), to: Graph
  @impl true
  defdelegate describe(gs), to: Graph
  @impl true
  defdelegate get(gs, opts), to: Graph
  @impl true
  defdelegate set(gs, opts), to: Graph
  @impl true
  defdelegate delete(gs, opts), to: Graph
  @impl true
  defdelegate observe(gs, opts), to: Graph
  @impl true
  defdelegate enter(gs, zone), to: Graph
  @impl true
  defdelegate exit(gs, zone), to: Graph
  @impl true
  defdelegate discover(gs, zone), to: Graph
end
