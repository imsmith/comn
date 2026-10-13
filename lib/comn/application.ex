defmodule Comn.Application do
  @moduledoc """
  OTP application entry point.

  Starts `Comn.Supervisor`, then runs two discovery passes once the
  supervision tree is up: `Comn.Errors.Registry.discover/0` indexes every
  compiled error code, and `Comn.Discovery.discover/0` indexes every module
  implementing the `Comn` behaviour.

  Started automatically when `:comn` is a dependency; there is nothing to
  add to your own supervision tree.
  """

  use Application

  @doc "Starts `Comn.Supervisor` and runs error-code and module discovery."
  @impl true
  def start(_type, _args) do
    result = Comn.Supervisor.start_link()

    # Index all compiled error codes and Comn modules after processes are running.
    Comn.Errors.Registry.discover()
    Comn.Discovery.discover()

    result
  end
end
