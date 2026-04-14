defmodule Comn.EventBus do
  @moduledoc """
  Local pub/sub via Elixir Registry.

  A lightweight event bus that uses `Registry` for topic-based dispatch.
  Subscribers receive `{:event, topic, payload}` messages.

  Requires `Registry.start_link(keys: :duplicate, name: Comn.EventBus)` in
  your supervision tree.

  Also implements `@behaviour Comn` for uniform introspection.

  ## Examples

      iex> Comn.EventBus.look()
      "EventBus — local pub/sub via Elixir Registry"

      iex> %{backend: :registry} = Comn.EventBus.recon()
  """

  @behaviour Comn

  @doc "Subscribes the calling process to `topic`. Messages arrive as `{:event, topic, payload}`."
  @spec subscribe(term()) :: {:ok, pid()} | {:error, term()}
  def subscribe(topic) do
    Registry.register(__MODULE__, topic, [])
  end

  @doc "Dispatches `payload` to all processes subscribed to `topic`."
  @spec broadcast(term(), term()) :: :ok
  def broadcast(topic, payload) do
    Registry.dispatch(__MODULE__, topic, fn entries ->
      for {pid, _} <- entries, do: send(pid, {:event, topic, payload})
    end)
  end

  # Comn callbacks

  @impl Comn
  def look, do: "EventBus — local pub/sub via Elixir Registry"

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
