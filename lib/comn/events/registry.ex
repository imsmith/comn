defmodule Comn.Events.Registry do
  @moduledoc """
  Adapts the built-in Elixir Registry to the `Comn.Events` system.

  Functionally identical to `Comn.EventBus` — both use `Registry` dispatch.
  This module exists as a named adapter within the `Comn.Events` namespace.

  Also implements `@behaviour Comn` for uniform introspection.

  ## Examples

      iex> Comn.Events.Registry.look()
      "Events.Registry — Elixir Registry adapter for the Comn.Events system"
  """

  @behaviour Comn

  def subscribe(topic) do
    Registry.register(__MODULE__, topic, [])
  end

  def broadcast(topic, payload) do
    Registry.dispatch(__MODULE__, topic, fn entries ->
      for {pid, _} <- entries, do: send(pid, {:event, topic, payload})
    end)
  end

  # Comn callbacks

  @impl Comn
  def look, do: "Events.Registry — Elixir Registry adapter for the Comn.Events system"

  @impl Comn
  def recon do
    %{
      backend: :registry,
      scope: :local,
      type: :implementation
    }
  end

  @impl Comn
  def choices do
    %{actions: ["subscribe", "broadcast"]}
  end

  @impl Comn
  def act(%{action: :subscribe, topic: topic}), do: subscribe(topic)
  def act(%{action: :broadcast, topic: topic, payload: payload}), do: {:ok, broadcast(topic, payload)}
  def act(_input), do: {:error, :unknown_action}
end
