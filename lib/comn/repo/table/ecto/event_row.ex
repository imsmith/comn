if Code.ensure_loaded?(Ecto.Schema) do
  defmodule Comn.Repo.Table.Ecto.EventRow do
    @moduledoc """
    The default schema of the `:ecto` table backend: the EventStruct as a
    row. The table is named after the Comn table (the handle name), so
    `schema "comn_events"` here is only a placeholder source.

    `kind` records whether the row was written as an event
    (`set(t, event: e)`) or as a plain key/value (`set(t, key, value)`,
    stored with `id: key` and `data: value`), so reads give back exactly
    what was written.
    """

    use Ecto.Schema

    alias Comn.Repo.Table.Ecto.Term

    @primary_key {:id, Term, autogenerate: false}
    schema "comn_events" do
      field(:kind, Term)
      field(:timestamp, :string)
      field(:source, Term)
      field(:type, Term)
      field(:topic, :string)
      field(:data, Term)
      field(:schema, :string)
      field(:version, :integer)
      field(:tags, Term)
      field(:correlation_id, :string)
      field(:request_id, :string)
      field(:metadata, Term)
    end

    @event_fields ~w(id timestamp source type topic data schema version tags correlation_id request_id metadata)a

    @doc false
    def attrs_for_event(%Comn.Events.EventStruct{} = e) do
      e |> Map.from_struct() |> Map.take(@event_fields) |> Map.put(:kind, :event)
    end

    @doc false
    def attrs_for_value(name, key, value) do
      %{
        id: key,
        kind: :value,
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
        source: Comn.Repo.Table,
        type: :domain,
        topic: Atom.to_string(name),
        data: value,
        version: 1,
        tags: [],
        metadata: %{}
      }
    end

    @doc false
    def to_value(%__MODULE__{kind: :value, data: data}), do: data

    def to_value(%__MODULE__{kind: :event} = row) do
      struct(Comn.Events.EventStruct, row |> Map.from_struct() |> Map.take(@event_fields))
    end
  end
end
