defmodule Comn.Repo.Handle do
  @moduledoc """
  Opaque handle returned by every shape's `open/2`.

  Carries the shape (facade module), the backend module, the backend's
  private state, the resource name, and shape-specific `meta` (a queue's
  discipline, for instance). Callers pass it back to the shape's verbs
  and should not inspect or build it directly.
  """

  @enforce_keys [:shape, :backend, :state, :name]
  defstruct [:shape, :backend, :state, :name, meta: %{}]

  @type t :: %__MODULE__{
          shape: module(),
          backend: module(),
          state: term(),
          name: term(),
          meta: map()
        }
end
