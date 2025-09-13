defmodule Comn.Events.NATS do
  @moduledoc """
  NATS adapter for the Comn.Events system.
  """

  def start_link(server \\ %{host: "127.0.0.1", port: 4222}, _opts) do
    Gnat.start_link(%{host: server.host, port: server.port})
  end

  def subscribe(conn_pid, topic, _opts) do
    Gnat.sub(conn_pid, topic, fn msg -> handle_message(msg) end)
  end

  def broadcast(conn_pid, topic, payload, _opts) do
    Gnat.pub(conn_pid, topic, payload)
  end

  defp handle_message(%Gnat.Message{topic: topic, body: body}) do
    IO.puts "Received message on topic #{topic}: #{body}"
    # Handle incoming NATS messages
  end
end
