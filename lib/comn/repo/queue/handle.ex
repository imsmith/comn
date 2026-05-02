defmodule Comn.Repo.Queue.Handle do
  @moduledoc false

  # Opaque handle returned by Comn.Repo.Queue.open/2. Callers should
  # treat this as a black box.

  @enforce_keys [:backend, :state, :name, :discipline]
  defstruct [:backend, :state, :name, :discipline]

  @type t :: %__MODULE__{
          backend:    module(),
          state:      term(),
          name:       term(),
          discipline: :fifo | :lifo
        }
end
