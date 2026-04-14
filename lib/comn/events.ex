defmodule Comn.Events do
  @moduledoc """
  Behaviour for pub/sub event systems.

  Defines four callbacks — `start_link`, `broadcast`, `subscribe`,
  `unsubscribe` — that adapters implement to bridge different event
  transports (Registry, NATS, etc.) behind a common interface.

  Also implements `@behaviour Comn` for uniform introspection.

  ## Examples

      iex> Comn.Events.look()
      "Events — pub/sub event system behaviour (start_link, broadcast, subscribe, unsubscribe)"

      iex> %{adapters: adapters} = Comn.Events.recon()
      iex> Comn.Events.NATS in adapters
      true
  """

  @behaviour Comn

  alias Comn.Events.EventStruct

  @doc """
  Starts the event adapter process. Add to a supervision tree.

  Errors: adapter-specific connection failures (e.g. `events.nats/connection_failed`).
  """
  @callback start_link(keyword()) :: {:ok, pid()} | {:error, term()}

  @doc "Publishes an event to all subscribers of its topic."
  @callback broadcast(EventStruct.t()) :: :ok | {:error, term()}

  @doc "Subscribes the calling process to events on `topic`."
  @callback subscribe(topic :: String.t(), opts :: keyword()) :: :ok | {:error, term()}

  @doc "Removes the calling process's subscription to `topic`."
  @callback unsubscribe(topic :: String.t(), opts :: keyword()) :: :ok | {:error, term()}

  @impl Comn
  def look, do: "Events — pub/sub event system behaviour (start_link, broadcast, subscribe, unsubscribe)"

  @impl Comn
  def recon do
    %{
      callbacks: [:start_link, :broadcast, :subscribe, :unsubscribe],
      adapters: [Comn.Events.NATS, Comn.EventBus, Comn.Events.Registry],
      type: :behaviour
    }
  end

  @impl Comn
  def choices do
    %{adapters: ["NATS", "EventBus", "Registry"]}
  end

  @impl Comn
  def act(_input), do: {:error, :behaviour_only}
end
