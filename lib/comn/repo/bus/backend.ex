defmodule Comn.Repo.Bus.Backend do
  @moduledoc false
  # Private contract implemented by Comn.Repo.Bus.Registry (and a future
  # NATS core backend). Callers go through Comn.Repo.Bus. The facade owns
  # the subscriber registry; a backend delivers by calling
  # Comn.Repo.Bus.notify/2 for every published event that should reach
  # local subscribers.

  alias Comn.Events.EventStruct

  @type state :: term()

  @callback open(name :: atom(), opts :: keyword()) :: {:ok, state()} | {:error, term()}
  @callback close(state()) :: :ok
  @callback drop(state()) :: :ok
  @callback publish(state(), EventStruct.t()) :: :ok | {:error, term()}
  @doc "Prepare live delivery (e.g. open a transport subscription). Called on each subscribe."
  @callback subscribe(state()) :: :ok | {:error, term()}
end
