defmodule Comn.Repo.Column.Backend do
  @moduledoc false
  # Private contract behind Comn.Repo.Column. Callers go through the facade.

  @type state :: term()
  @type schema :: Comn.Repo.Column.schema()
  @type row :: Comn.Repo.Column.row()
  @type filters :: Comn.Repo.Column.filters()

  @callback open(name :: atom(), opts :: keyword()) :: {:ok, state()} | {:error, term()}
  @callback close(state()) :: :ok
  @callback drop(state()) :: :ok
  @callback define_schema(state(), schema()) :: :ok | {:error, term()}
  @callback schema(state()) :: {:ok, schema()} | {:error, term()}
  @callback append_row(state(), row()) :: :ok | {:error, term()}
  @callback append_rows(state(), [row()]) :: :ok | {:error, term()}
  @callback flush(state()) :: {:ok, non_neg_integer()} | {:error, term()}
  @callback project(state(), fields :: [atom()], filters()) :: {:ok, [row()]} | {:error, term()}
  @callback count(state(), filters()) :: {:ok, non_neg_integer()} | {:error, term()}
  @callback describe(state()) :: {:ok, map()} | {:error, term()}
  @callback get(state(), keyword()) :: {:ok, term()} | {:error, term()}
  @callback set(state(), keyword()) :: :ok | {:error, term()}
  @callback delete(state(), keyword()) :: :ok | {:error, term()}
  @callback observe(state(), keyword()) :: Enumerable.t() | {:error, term()}
end
