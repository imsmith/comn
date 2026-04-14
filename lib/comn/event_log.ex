defmodule Comn.EventLog do
  @moduledoc """
  In-memory, append-only event log backed by an `Agent`.

  Records structs that implement the `Comn.Event` protocol and provides
  query functions by topic, type, and timestamp. Useful for audit trails,
  replay, and debugging.

  Also implements `@behaviour Comn` for uniform introspection.

  ## Examples

      iex> Comn.EventLog.look()
      "EventLog — in-memory immutable event log for agent/tool activity"

      iex> %{queries: qs} = Comn.EventLog.recon()
      iex> :for_topic in qs
      true
  """

  @behaviour Comn

  use Agent

  alias Comn.Event

  @type event :: struct()

  ## Public API

  def start_link(_opts) do
    Agent.start_link(fn -> [] end, name: __MODULE__)
  end

  @doc "Records any struct that implements the Comn.Event protocol."
  @spec record(term()) :: :ok
  def record(term) do
    event = Event.to_event(term)
    Agent.update(__MODULE__, fn log -> [event | log] end)
  end

  @doc "Returns all logged events, oldest to newest."
  @spec all() :: [event]
  def all do
    Agent.get(__MODULE__, &Enum.reverse/1)
  end

  @doc "Returns all events matching a topic."
  @spec for_topic(String.t()) :: [event]
  def for_topic(topic) do
    Agent.get(__MODULE__, fn log ->
      log
      |> Enum.filter(&(&1.topic == topic))
      |> Enum.reverse()
    end)
  end

  @doc "Returns all events of a given type (e.g., :start, :stop, :message)."
  @spec for_type(atom()) :: [event]
  def for_type(type) do
    Agent.get(__MODULE__, fn log ->
      log
      |> Enum.filter(&(&1.type == type))
      |> Enum.reverse()
    end)
  end

  @doc "Returns all events newer than an ISO8601 datetime string."
  @spec since(String.t()) :: [event]
  def since(iso_timestamp) do
    {:ok, dt, _} = DateTime.from_iso8601(iso_timestamp)

    Agent.get(__MODULE__, fn log ->
      log
      |> Enum.filter(fn event ->
        case DateTime.from_iso8601(event.timestamp) do
          {:ok, t, _} -> DateTime.compare(t, dt) == :gt
          _ -> false
        end
      end)
      |> Enum.reverse()
    end)
  end

  @doc "Clears the event log. Use with caution."
  def clear do
    Agent.update(__MODULE__, fn _ -> [] end)
  end

  # Comn callbacks

  @impl Comn
  def look, do: "EventLog — in-memory immutable event log for agent/tool activity"

  @impl Comn
  def recon do
    %{
      storage: :agent,
      queries: [:all, :for_topic, :for_type, :since],
      immutable: true,
      type: :implementation
    }
  end

  @impl Comn
  def choices do
    %{actions: ["record", "all", "for_topic", "for_type", "since", "clear"]}
  end

  @impl Comn
  def act(%{action: :record, event: event}), do: {:ok, record(event)}
  def act(%{action: :all}), do: {:ok, all()}
  def act(%{action: :for_topic, topic: topic}), do: {:ok, for_topic(topic)}
  def act(%{action: :for_type, type: type}), do: {:ok, for_type(type)}
  def act(%{action: :since, timestamp: ts}), do: {:ok, since(ts)}
  def act(_input), do: {:error, :unknown_action}
end
