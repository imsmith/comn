
defmodule Comn.Repo.Graphs do
  @moduledoc """
  A behavior defining the interface for graph database operations and queries.
  """

  @optional_callbacks graph_info: 0
  @optional_callbacks query_graph: 2
  @optional_callbacks query_graph!: 2

  ## GRAPH
  @callback graph_create(Comn.Repo.Graph.t()) :: any()
  @callback graph_delete() :: any()
  @callback graph_info() :: any()
  @callback graph_read() :: any()
  @callback graph_update(Comn.Repo.Graph.t()) :: any()

  ## QUERY
  @callback query_graph(Comn.Repo.Graph.t()) :: any()
  @callback query_graph!(Comn.Repo.Graph.t()) :: any()
  @callback query_graph(Comn.Repo.Graph.t(), map()) :: any()
  @callback query_graph!(Comn.Repo.Graph.t(), map()) :: any()

end
