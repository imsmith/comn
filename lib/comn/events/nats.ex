defmodule Comn.Events.NATS do
  @moduledoc """
  NATS adapter for the Comn.Events system.

  Wraps a Gnat connection in a GenServer that manages subscriptions
  and translates NATS messages into EventStruct broadcasts on the local EventBus.
  """

  use GenServer

  alias Comn.Events.EventStruct
  alias Comn.EventBus

  # Client API

  @doc "Starts a NATS connection. Options are passed to Gnat.start_link."
  def start_link(opts \\ []) do
    {server_opts, gen_opts} = Keyword.split(opts, [:host, :port, :tls, :ssl_opts])
    server = Map.new(server_opts)
    server = if map_size(server) == 0, do: %{host: "127.0.0.1", port: 4222}, else: server
    GenServer.start_link(__MODULE__, server, gen_opts)
  end

  @doc "Subscribes the calling process to a NATS topic. Messages are forwarded to the local EventBus."
  def subscribe(pid, topic) do
    GenServer.call(pid, {:subscribe, topic, self()})
  end

  @doc "Unsubscribes from a NATS topic."
  def unsubscribe(pid, subscription_id) do
    GenServer.call(pid, {:unsubscribe, subscription_id})
  end

  @doc "Publishes a payload to a NATS topic."
  def broadcast(pid, topic, payload) do
    GenServer.call(pid, {:broadcast, topic, payload})
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
end
