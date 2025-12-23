defmodule Comn.Repo.File do
  @moduledoc """
  A behavior defining the interface for file repository operations.
  """

  @callback file_create(term(), keyword()) :: :ok | {:error, term()}
  @callback file_delete(term(), keyword()) :: :ok | {:error, term()}
  @callback file_update(term(), keyword()) :: :ok | {:error, term()}

  @callback file_open(term(), keyword()) :: {:ok, term()} | {:error, term()}
  @callback file_close(term(), keyword()) :: :ok | {:error, term()}
  @callback file_info(term(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback file_exists?(term(), keyword()) :: boolean()
  @callback file_list(term(), keyword()) :: {:ok, [term()]} | {:error, term()}

  @callback file_read(term(), keyword()) :: {:ok, term()} | {:error, term()}
  @callback file_stream(term(), keyword()) :: Enumerable.t() | {:error, term()}
  @callback file_publish(term(), keyword()) :: :ok | {:error, term()}

  @callback file_subscribe(term(), keyword()) :: Enumerable.t() | {:error, term()}
  @callback file_unsubscribe(term(), keyword()) :: :ok | {:error, term()}
end
