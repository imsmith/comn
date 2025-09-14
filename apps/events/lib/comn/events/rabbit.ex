defmodule Comn.Events.Rabbit do
  @moduledoc """
  RabbitMQ adapter for the Comn.Events system.
  """

  use AMQP

  def start_link(_opts) do
    AMQP.Connection.open("amqp://guest:guest@localhost")
  end

  def subscribe(conn, topic) do
    AMQP.Queue.declare(conn, topic)
    AMQP.Basic.consume(conn, topic, nil, no_ack: true)
  end

  def broadcast(conn, exchange, routing_key, payload) do
    AMQP.Basic.publish(conn, exchange, routing_key, payload)
  end
end
