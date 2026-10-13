defmodule Comn.Repo.Table.Handle do
  @moduledoc """
  Opaque handle returned by `Comn.Repo.Table.open/2`.

  Carries the backend module, its private state, and the table name.
  Callers pass it back to every `Comn.Repo.Table` function.
  """

  @enforce_keys [:backend, :state, :name]
  defstruct [:backend, :state, :name]

  @type t :: %__MODULE__{backend: module(), state: term(), name: atom()}
end
