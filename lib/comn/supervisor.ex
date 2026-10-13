defmodule Comn.Supervisor do
  @moduledoc """
  Top-level supervisor for Comn's stateful processes.

  Add to your application's supervision tree:

      children = [
        Comn.Supervisor,
        # ... your own children
      ]

  Starts:

  - `Comn.EventBus` — Registry-based pub/sub (`:duplicate` keys)
  - `Comn.Events.Registry` — Registry-based event adapter (`:duplicate` keys)
  - `Comn.EventLog` — Agent-backed append-only event log
  - `Comn.Presence` — Agent-backed zone-scoped actor presence
  - `Comn.Repo.Table.Ecto.Supervisor` — dynamic Ecto repos built from configuration

  Error-code and module discovery run after this supervisor is up; see
  `Comn.Application`.

  Optional processes like `Comn.Events.NATS` are not started here — add
  them to your own supervision tree with the appropriate connection config.
  """

  use Supervisor

  @doc "Starts the Comn supervisor and its child processes."
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      {Registry, keys: :duplicate, name: Comn.EventBus},
      {Registry, keys: :duplicate, name: Comn.Events.Registry},
      Comn.EventLog,
      Comn.Presence,
      # Dynamic Ecto repos built from configuration by Comn.Repo.Table.Ecto
      {DynamicSupervisor, name: Comn.Repo.Table.Ecto.Supervisor, strategy: :one_for_one}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
