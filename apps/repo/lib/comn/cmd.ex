defmodule Comn.Repo.Cmd do
  @moduledoc """
  A behavior to handle command-line arguments and execute the appropriate functions.
  """

  @doc """
  Parses command-line arguments and executes the corresponding function.
  """



  @callback validate(term(), keyword()) :: :ok | {:error, term()}
  @callback apply(term(), keyword()) :: :ok | {:error, term()}
  @callback reset(term(), keyword()) :: :ok | {:error, term()}
  @callback enable(term(), keyword()) :: :ok | {:error, term()}
  @callback disable(term(), keyword()) :: :ok | {:error, term()}
  @callback sync(term(), keyword()) :: :ok | {:error, term()}
  @callback status(term(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback test(term(), keyword()) :: :ok | {:error, term()}
  @callback invoke(term(), keyword()) :: :ok | {:error, term()}
  @callback info(term()) :: {:ok, map()} | {:error, term()}
  @callback watch(term(), keyword()) :: Enumerable.t() | {:error, term()}
  @callback run(term(), keyword()) :: :ok | {:error, term()}
  @callback probe(term(), keyword()) :: :ok | {:error, term()}
end
