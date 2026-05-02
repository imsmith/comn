defmodule Comn.Repo.Queue.Backend do
  @moduledoc false

  # Private contract implemented by Comn.Repo.Queue.Mem and
  # Comn.Repo.Queue.SQLite. Callers should never name this module
  # or any of its implementations; they use Comn.Repo.Queue.

  @type state :: term()
  @type token :: term()
  @type item  :: term()

  @callback open(name :: term(), opts :: keyword()) ::
              {:ok, state()} | {:error, term()}

  @callback close(state()) :: :ok

  @callback push(state(), item()) :: :ok | {:error, term()}

  @callback reserve(state()) ::
              {:ok, {token(), item()}} | :empty | {:error, term()}

  @callback ack(state(), token()) :: :ok | {:error, term()}

  @callback release(state(), token()) :: :ok | {:error, term()}

  @callback peek(state(), pos_integer()) :: [item()]

  @callback size(state()) :: non_neg_integer()

  @callback find(state(), (item() -> boolean())) ::
              {:ok, item()} | :not_found

  @callback remove(state(), (item() -> boolean())) ::
              {:ok, item()} | :not_found
end
