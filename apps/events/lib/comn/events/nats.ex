defmodule Comn.Events.NATS do
  @moduledoc """
  NATS adapter for the Comn.Events system.
  Wraps a Gnat connection in a GenServer for ergonomic API usage.
  """

  use GenServer

  # Client API

  def start_link(server \\ %{host: "127.0.0.1", port: 4222}, opts \\ []) do
    GenServer.start_link(__MODULE__, {server, opts})
  end

  def subscribe(server_pid, topic, opts \\ []) do
    GenServer.call(server_pid, {:subscribe, topic, opts})
  end

  def broadcast(server_pid, topic, payload, opts \\ []) do
    GenServer.call(server_pid, {:broadcast, topic, payload, opts})
  end

  # Server (GenServer) callbacks

  @impl true
  def init({server, opts}) do
    case Gnat.start_link(%{host: server.host, port: server.port}, opts) do
      {:ok, conn_pid} ->
        {:ok, %{conn_pid: conn_pid}}
      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call({:subscribe, topic, opts}, _from, state) do
    :ok = Gnat.sub(state.conn_pid, topic, opts, fn msg -> handle_message(msg) end)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:broadcast, topic, payload, opts}, _from, state) do
    :ok = Gnat.pub(state.conn_pid, topic, payload, opts)
    {:reply, :ok, state}
  end

  defp handle_message(%{topic: topic, body: body}) do
    IO.puts "Received message on topic #{topic}: #{body}"
    # Handle incoming NATS messages
  end
end
