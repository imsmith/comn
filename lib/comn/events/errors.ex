defmodule Comn.Events.Errors do
  @moduledoc """
  Registered error codes for the `Comn.Events` subsystem.
  """

  use Comn.Errors.Registry

  register_error "events.nats/connection_failed", :network, message: "Could not connect to NATS server"
  register_error "events/invalid_type",           :validation, message: "Unknown event type string — not a registered atom"
end
