defmodule Comn.Repo.Table.Backend do
  @moduledoc false
  # Private contract behind Comn.Repo.Table. Callers go through the facade.
  # `opts` on the verbs carry per-call options such as schema: for backends
  # that understand them; others ignore them.

  @type state :: term()

  @callback open(name :: atom(), opts :: keyword()) :: {:ok, state()} | {:error, term()}
  @callback close(state()) :: :ok
  @callback drop(state()) :: :ok
  @callback get(state(), key :: term(), opts :: keyword()) :: {:ok, term()} | {:error, term()}
  @callback set(state(), key :: term(), value :: term(), opts :: keyword()) ::
              :ok | {:error, term()}
  @callback delete(state(), key :: term(), opts :: keyword()) :: :ok | {:error, term()}
  @callback keys(state(), opts :: keyword()) :: {:ok, [term()]} | {:error, term()}
  @callback count(state(), opts :: keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  @callback observe(state(), opts :: keyword()) :: [{term(), term()}] | {:error, term()}
end
