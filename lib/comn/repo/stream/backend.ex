defmodule Comn.Repo.Stream.Backend do
  @moduledoc false
  # Private contract implemented by Comn.Repo.Stream.{Mem, SQLite, JetStream}.
  # Callers never name this module or its implementations; they go through
  # Comn.Repo.Stream. Events arriving here are already validated EventStructs.
  #
  # Live delivery: a backend calls Comn.Repo.Stream.notify/3 for every
  # appended event; the facade owns the subscriber registry.

  alias Comn.Events.EventStruct

  @type state :: term()
  @type offset :: term()
  @type cursor :: offset() | :head | :tail

  @callback open(name :: atom(), opts :: keyword()) :: {:ok, state()} | {:error, term()}
  @callback close(state()) :: :ok
  @callback drop(state()) :: :ok
  @callback append(state(), [EventStruct.t()]) :: {:ok, [offset()]} | {:error, term()}
  @callback read(state(), cursor(), pos_integer()) ::
              {:ok, [{offset(), EventStruct.t()}]} | {:error, term()}
  @callback head(state()) :: {:ok, offset() | nil} | {:error, term()}
  @callback tail(state()) :: {:ok, offset() | nil} | {:error, term()}
  @callback count(state()) :: {:ok, non_neg_integer()} | {:error, term()}
  @doc "Prepare live delivery (e.g. create a push consumer). Called on each subscribe."
  @callback subscribe(state()) :: :ok | {:error, term()}
end
