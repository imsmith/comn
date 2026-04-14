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

  @callback start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  @callback broadcast(EventStruct.t()) :: :ok | {:error, term()}
  @callback subscribe(topic :: String.t(), opts :: keyword()) :: :ok | {:error, term()}
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
