defmodule Comn.Repo.Graphs.Backend do
  @moduledoc false
  # Private contract behind Comn.Repo.Graphs. Callers go through the facade.
  # Mutating verbs return {:ok, state} because a graph is a value; the facade
  # re-binds it into the handle.

  @type state :: term()

  @callback open(name :: term(), opts :: keyword()) :: {:ok, state()} | {:error, term()}
  @callback close(state()) :: :ok
  @callback drop(state()) :: :ok
  @callback link(state(), from :: term(), to :: term(), opts :: keyword()) ::
              {:ok, state()} | {:error, term()}
  @callback unlink(state(), from :: term(), to :: term(), opts :: keyword()) ::
              {:ok, state()} | {:error, term()}
  @callback traverse(state(), query :: keyword()) :: {:ok, term()} | {:error, term()}
  @callback traverse(state(), from :: Comn.Zone.t(), to :: term(), opts :: keyword()) ::
              {:ok, term()} | {:error, term()}
  @callback describe(state()) :: {:ok, map()} | {:error, term()}
  @callback get(state(), keyword()) :: {:ok, term()} | {:error, term()}
  @callback set(state(), keyword()) :: {:ok, state()} | {:error, term()}
  @callback delete(state(), keyword()) :: {:ok, state()} | {:error, term()}
  @callback observe(state(), keyword()) :: Enumerable.t() | {:ok, map()} | {:error, term()}
  @callback enter(state(), Comn.Zone.t()) :: {:ok, term()} | {:error, term()}
  @callback exit(state(), Comn.Zone.t()) :: :ok | {:error, term()}
  @callback discover(state(), Comn.Zone.t()) :: {:ok, list()} | {:error, term()}
end
