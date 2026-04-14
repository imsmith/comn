defmodule Comn.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    result = Comn.Supervisor.start_link()

    # Index all compiled error codes and Comn modules after processes are running.
    Comn.Errors.Registry.discover()
    Comn.Discovery.discover()

    result
  end
end
