defmodule Comn.Repo.File.Backend do
  @moduledoc false
  # Private contract behind Comn.Repo.File. Callers go through the facade.
  # State is the file's lifecycle value; verbs that advance it return
  # {:ok, state} and the facade re-binds it into the handle.

  @type state :: term()

  @callback open(path_or_ref :: term(), opts :: keyword()) :: {:ok, state()} | {:error, term()}
  @callback close(state()) :: :ok
  @callback drop(state()) :: :ok
  @callback load(state(), keyword()) :: {:ok, state()} | {:error, term()}
  @callback stream(state(), keyword()) :: {:ok, Enumerable.t()} | {:error, term()}
  @callback cast(state(), keyword()) :: :ok | {:error, term()}
  @callback read(state(), keyword()) :: {:ok, binary()} | {:error, term()}
  @callback write(state(), iodata(), keyword()) :: {:ok, state()} | {:error, term()}
  @callback describe(state()) :: {:ok, map()} | {:error, term()}
  @callback get(state(), keyword()) :: {:ok, term()} | {:error, term()}
  @callback set(state(), keyword()) :: {:ok, state()} | {:error, term()}
  @callback delete(state(), keyword()) :: :ok | {:error, term()}
  @callback observe(state(), keyword()) :: Enumerable.t() | {:error, term()}
end
