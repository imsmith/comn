defmodule Comn.Repo.Table do
  @moduledoc """
  Behaviour for table-style key-value repositories.

  Extends the base Comn.Repo behaviour with table-specific operations.
  """

  @callback create(name :: atom(), opts :: keyword()) :: {:ok, term()} | {:error, term()}
  @callback drop(name :: atom()) :: :ok | {:error, term()}
  @callback keys(name :: atom()) :: {:ok, [term()]} | {:error, term()}
  @callback count(name :: atom()) :: {:ok, non_neg_integer()} | {:error, term()}
end
