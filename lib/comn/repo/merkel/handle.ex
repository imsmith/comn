defmodule Comn.Repo.Merkel.Handle do
  @moduledoc """
  Opaque handle returned by `Comn.Repo.Merkel.open/2`.

  Carries the backend module, its private state, and the merkel name.
  Callers pass it back to every `Comn.Repo.Merkel` function.
  """

  @enforce_keys [:backend, :state, :name]
  defstruct [:backend, :state, :name]

  @type t :: %__MODULE__{backend: module(), state: term(), name: atom()}
end
