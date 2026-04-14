defmodule Comn.Events.EventStruct do
  @moduledoc """
  Concrete event struct for immutable system activity logs.

  When a process has an ambient `Comn.Contexts` set, the constructor
  automatically pulls `request_id` and `correlation_id` from it.

  ## Fields

  - `id` — unique event ID (UUID, auto-generated)
  - `timestamp` — ISO 8601 string
  - `type` — event type atom (e.g. `:domain`, `:system`)
  - `topic` — routing topic string (e.g. `"user.created"`)
  - `source` — originating module, pid, or name
  - `data` — event payload
  - `schema` — identifies the shape of `data` (e.g. `"user.created.v1"`)
  - `version` — integer format version for schema evolution (default `1`)
  - `tags` — list of strings for ad-hoc filtering (e.g. `["priority:high"]`)
  - `correlation_id` — auto-pulled from ambient context
  - `request_id` — auto-pulled from ambient context
  - `metadata` — arbitrary map for extension data

  ## Examples

      iex> event = Comn.Events.EventStruct.new(:test, "user.created", %{id: 1})
      iex> event.type
      :test
      iex> is_binary(event.id)
      true
      iex> event.version
      1
      iex> event.tags
      []
  """

  @enforce_keys [:type, :topic]
  defstruct [
    :id,
    :timestamp,
    :source,
    :type,
    :topic,
    :data,
    :schema,
    :correlation_id,
    :request_id,
    version: 1,
    tags: [],
    metadata: %{}
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          timestamp: String.t(),
          source: atom() | pid() | binary(),
          type: atom(),
          topic: String.t(),
          data: any(),
          schema: String.t() | nil,
          version: pos_integer(),
          tags: [String.t()],
          correlation_id: String.t() | nil,
          request_id: String.t() | nil,
          metadata: map()
        }

  @doc """
  Creates a new event, auto-enriching from the ambient `Comn.Contexts` if present.

  Accepts an optional keyword list for `schema`, `version`, `tags`, and `metadata`:

      EventStruct.new(:domain, "order.placed", %{id: 1}, MyApp.Orders,
        schema: "order.placed.v2", version: 2, tags: ["priority:high"])
  """
  @spec new(atom(), String.t(), any(), atom() | pid() | binary(), keyword()) :: t()
  def new(type, topic, data, source \\ __MODULE__, opts \\ []) do
    ctx = Comn.Contexts.get()

    %__MODULE__{
      id: Comn.Secrets.Local.UUID.uuid4(),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      source: source,
      type: type,
      topic: topic,
      data: data,
      schema: Keyword.get(opts, :schema),
      version: Keyword.get(opts, :version, 1),
      tags: Keyword.get(opts, :tags, []),
      correlation_id: ctx && ctx.correlation_id,
      request_id: ctx && ctx.request_id,
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end
end
