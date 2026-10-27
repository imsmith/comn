defmodule Comn.Repo.Bus.Registry do
  @moduledoc false
  # Local bus backend. The facade already dispatches through the shared
  # Comn.EventBus registry, so this backend only has to hand each published
  # event back to it. Nothing to open, nothing to close, nothing retained.

  @behaviour Comn.Repo.Bus.Backend

  alias Comn.Repo.Bus

  @impl true
  def open(name, _opts) when is_atom(name), do: {:ok, name}

  @impl true
  def close(_name), do: :ok

  @impl true
  def drop(_name), do: :ok

  @impl true
  def publish(name, event), do: Bus.notify(name, event)

  @impl true
  def subscribe(_name), do: :ok
end
