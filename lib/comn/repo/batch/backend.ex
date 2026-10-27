defmodule Comn.Repo.Batch.Backend do
  @moduledoc false
  # Private contract behind Comn.Repo.Batch. Callers go through the facade.
  # close/1 flushes then releases; drop/1 releases and discards the buffer.

  @type state :: term()
  @type item :: Comn.Repo.Batch.item()

  @callback open(name :: atom(), opts :: keyword()) :: {:ok, state()} | {:error, term()}
  @callback close(state()) :: :ok
  @callback drop(state()) :: :ok
  @callback add(state(), item()) :: :ok | {:error, term()}
  @callback add_many(state(), [item()]) :: :ok | {:error, term()}
  @callback flush(state()) :: {:ok, non_neg_integer()} | {:error, term()}
  @callback pending(state()) :: {:ok, non_neg_integer()}
  @callback config(state()) :: {:ok, map()}
  @callback describe(state()) :: {:ok, map()} | {:error, term()}
  @callback get(state(), keyword()) :: {:ok, term()} | {:error, term()}
  @callback set(state(), keyword()) :: :ok | {:error, term()}
  @callback delete(state(), keyword()) :: :ok | {:error, term()}
  @callback observe(state(), keyword()) :: Enumerable.t() | {:error, term()}
end
