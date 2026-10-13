defmodule Comn.Repo.Stream.Handle do
  @moduledoc """
  Opaque handle returned by `Comn.Repo.Stream.open/2`.

  Carries the backend module, its private state, and the stream name.
  Callers pass it back to every `Comn.Repo.Stream` function and should
  not inspect or build it directly. Live messages carry `name`.
  """

  @enforce_keys [:backend, :state, :name]
  defstruct [:backend, :state, :name]

  @type t :: %__MODULE__{backend: module(), state: term(), name: atom()}
end
