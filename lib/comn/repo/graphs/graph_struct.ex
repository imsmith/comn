defmodule Comn.Repo.Graphs.GraphStruct do
  @moduledoc """
  Struct representing a graph in the repository.
  """

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t() | nil,
          graph: Graph.t(),
          directed?: boolean(),
          metadata: map()
        }

  @enforce_keys [:id, :graph]
  defstruct id: nil,
            name: nil,
            graph: nil,
            directed?: true,
            metadata: %{}
end
