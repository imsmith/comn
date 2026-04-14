defmodule Comn.Events.NATS do
  @moduledoc """
  NATS adapter for the `Comn.Events` system.

  Wraps a Gnat connection in a named GenServer that manages subscriptions
  and translates NATS messages into `Comn.Events.EventStruct` broadcasts
  on the local `Comn.EventBus`. Defaults to `127.0.0.1:4222`.

  Registers as `Comn.Events.NATS` by default. Pass `:name` to override.

  Not started by `Comn.Supervisor` — add to your own supervision tree
  with the appropriate connection config:

      children = [
        Comn.Supervisor,
        {Comn.Events.NATS, host: "nats.internal", port: 4222}
      ]

  Implements `@behaviour Comn` for uniform introspection.

  ## Examples

      iex> Comn.Events.NATS.look()
      "Events.NATS — NATS adapter bridging NATS pub/sub to local EventBus"

      iex> %{default_port: 4222} = Comn.Events.NATS.recon()
  """

  use GenServer

  @behaviour Comn

  alias Comn.Events.EventStruct
  alias Comn.EventBus

  # Client API

  @doc """
  Starts a NATS connection.

  Registers as `Comn.Events.NATS` by default. Pass `name: :my_nats` to override.

  Options: `:host`, `:port`, `:tls`, `:ssl_opts`, `:name`.
  """
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    {server_opts, gen_opts} = Keyword.split(opts, [:host, :port, :tls, :ssl_opts])
    server = Map.new(server_opts)
    server = if map_size(server) == 0, do: %{host: "127.0.0.1", port: 4222}, else: server
    GenServer.start_link(__MODULE__, server, [{:name, name} | gen_opts])
  end

  @doc """
  Subscribes the calling process to a NATS topic.

  Messages are forwarded to the local EventBus. Uses the default named
  process unless `:name` is provided.
  """
  def subscribe(topic, opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.call(name, {:subscribe, topic, self()})
  end

  @doc """
  Unsubscribes from a NATS topic by subscription ID.
  """
  def unsubscribe(subscription_id, opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.call(name, {:unsubscribe, subscription_id})
  end

  @doc """
  Publishes a payload to a NATS topic.
  """
  def broadcast(topic, payload, opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.call(name, {:broadcast, topic, payload})
  end

  # Server callbacks

  @impl true
  def init(server) do
    case Gnat.start_link(server) do
      {:ok, conn} ->
        {:ok, %{conn: conn, subscriptions: %{}}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call({:subscribe, topic, subscriber}, _from, state) do
    case Gnat.sub(state.conn, subscriber, topic) do
      {:ok, sid} ->
        subs = Map.put(state.subscriptions, sid, topic)
        {:reply, {:ok, sid}, %{state | subscriptions: subs}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:unsubscribe, sid}, _from, state) do
    result = Gnat.unsub(state.conn, sid)
    subs = Map.delete(state.subscriptions, sid)
    {:reply, result, %{state | subscriptions: subs}}
  end

  @impl true
  def handle_call({:broadcast, topic, payload}, _from, state) do
    encoded = if is_binary(payload), do: payload, else: inspect(payload)
    result = Gnat.pub(state.conn, topic, encoded)
    {:reply, result, state}
  end

  @doc """
  Handles incoming NATS messages and bridges them to the local EventBus.

  NATS delivers messages as `{:msg, %{topic: topic, body: body, ...}}`.
  We convert them to EventStruct and broadcast on the local EventBus.
  """
  @impl true
  def handle_info({:msg, %{topic: topic, body: body}}, state) do
    event = EventStruct.new(:nats_message, topic, %{body: body}, __MODULE__)
    EventBus.broadcast(topic, event)
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Comn callbacks

  @impl Comn
  def look, do: "Events.NATS — NATS adapter bridging NATS pub/sub to local EventBus"

  @impl Comn
  def recon do
    %{
      backend: :nats,
      default_host: "127.0.0.1",
      default_port: 4222,
      bridges_to: Comn.EventBus,
      type: :implementation
    }
  end

  @impl Comn
  def choices do
    %{
      host: "NATS server host (default: 127.0.0.1)",
      port: "NATS server port (default: 4222)",
      tls: [true, false]
    }
  end

  @impl Comn
  def act(%{action: :connect} = input) do
    opts = Map.to_list(Map.drop(input, [:action]))
    start_link(opts)
  end

  def act(%{action: :broadcast, topic: topic, payload: payload} = input) do
    opts = if Map.has_key?(input, :name), do: [name: input.name], else: []
    {:ok, broadcast(topic, payload, opts)}
  end

  def act(%{action: :subscribe, topic: topic} = input) do
    opts = if Map.has_key?(input, :name), do: [name: input.name], else: []
    subscribe(topic, opts)
  end

  def act(_input), do: {:error, :unknown_action}
end
