defmodule Comn.Events.Errors do
  @moduledoc """
  Registered error codes for the `Comn.Events` subsystem.
  """

  use Comn.Errors.Registry

  register_error "events.nats/connection_failed", :network, message: "Could not connect to NATS server"
end
