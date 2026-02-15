defmodule Comn.Repo.Graphs do
  @moduledoc """
  Behaviour for graph repository operations.

  Graphs are nodes and edges. Repo handles nodes via get/set/delete.
  This behaviour adds what's structurally unique to graphs: links and traversal.
  """

  alias Comn.Repo.Graphs.GraphStruct

  @callback link(graph :: GraphStruct.t(), from :: term(), to :: term(), opts :: keyword()) ::
              {:ok, GraphStruct.t()} | {:error, term()}

  @callback unlink(graph :: GraphStruct.t(), from :: term(), to :: term(), opts :: keyword()) ::
              {:ok, GraphStruct.t()} | {:error, term()}

  @callback traverse(graph :: GraphStruct.t(), query :: keyword()) ::
              {:ok, term()} | {:error, term()}
end
