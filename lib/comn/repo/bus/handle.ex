defmodule Comn.Repo.Bus.Handle do
  @moduledoc """
  Opaque handle returned by `Comn.Repo.Bus.open/2`.

  Carries the backend module, its private state, and the bus name.
  Callers pass it back to every `Comn.Repo.Bus` function. Live messages
  carry `name`.
  """

  @enforce_keys [:backend, :state, :name]
  defstruct [:backend, :state, :name]

  @type t :: %__MODULE__{backend: module(), state: term(), name: atom()}
end
