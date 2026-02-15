defmodule Comn.Repo.Graphs do
  @moduledoc """
  Behaviour for graph repository operations.
  """

  @callback graph_create(opts :: keyword()) ::
              {:ok, Comn.Repo.Graphs.GraphStruct.t()} | {:error, term()}

  @callback graph_delete(id :: term()) ::
              :ok | {:error, term()}

  @callback graph_info(id :: term()) ::
              {:ok, map()} | {:error, term()}

  @callback graph_read(id :: term()) ::
              {:ok, Comn.Repo.Graphs.GraphStruct.t()} | {:error, term()}

  @callback graph_update(id :: term(), updates :: keyword()) ::
              {:ok, Comn.Repo.Graphs.GraphStruct.t()} | {:error, term()}

  @callback query_graph(id :: term(), query :: keyword()) ::
              {:ok, term()} | {:error, term()}
end
