defmodule Comn.Repo.Queue.Handle do
  @moduledoc """
  Opaque handle returned by `Comn.Repo.Queue.open/2`.

  Carries the backend module, its private state, the queue name, and the
  discipline (`:fifo` or `:lifo`). Callers pass it back to every
  `Comn.Repo.Queue` function and should not inspect or build it directly.
  """

  @enforce_keys [:backend, :state, :name, :discipline]
  defstruct [:backend, :state, :name, :discipline]

  @type t :: %__MODULE__{
          backend:    module(),
          state:      term(),
          name:       term(),
          discipline: :fifo | :lifo
        }
end
