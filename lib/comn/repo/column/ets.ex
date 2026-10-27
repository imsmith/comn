defmodule Comn.Repo.Column.ETS do
  @moduledoc """
  ETS-backed implementation of `Comn.Repo.Column` and `Comn.Repo`.

  In-memory column store: one named ETS ordered_set per store, under the
  caller's atom. Rows live under integer keys in insertion order; the
  schema and counters live under atom keys in the same table. Appends
  write straight to ETS, so `flush/1` is a no-op that reports the count.

  Intended for development, testing, and small datasets. Not a substitute
  for a real column store on large data.

  Implements `@behaviour Comn` for uniform introspection.

  ## Examples

      iex> {:ok, store} = Comn.Repo.Column.ETS.create(:metrics)
      iex> :ok = Comn.Repo.Column.ETS.define_schema(store, %{ts: :datetime, host: :string, cpu: :float})
      iex> :ok = Comn.Repo.Column.ETS.append_row(store, %{ts: "2024-01-01T00:00:00Z", host: "web-1", cpu: 0.42})
      iex> {:ok, 1} = Comn.Repo.Column.ETS.flush(store)
      iex> {:ok, rows} = Comn.Repo.Column.ETS.project(store, [:host, :cpu], %{})
      iex> hd(rows).host
      "web-1"
      iex> Comn.Repo.Column.ETS.drop(store)
      :ok
  """

  @behaviour Comn
  @behaviour Comn.Repo
  @behaviour Comn.Repo.Column

  alias Comn.Errors.Registry, as: ErrReg

  @enforce_keys [:name]
  defstruct [:name]

  @type t :: %__MODULE__{name: atom()}

  # Rows are {integer_id, row}; metadata is {atom_key, value} in the same table.
  @rows [{{:"$1", :"$2"}, [{:is_integer, :"$1"}], [:"$2"]}]

  # -- Lifecycle --

  @doc "Creates a new column store. Returns a store handle."
  @spec create(atom()) :: {:ok, t()} | {:error, term()}
  def create(name) when is_atom(name) do
    if table_exists?(name) do
      {:error, ErrReg.error!("repo.column/already_exists", field: name)}
    else
      :ets.new(name, [:named_table, :public, :ordered_set])
      :ets.insert(name, [{:schema, nil}, {:row_count, 0}, {:next_id, 0}])
      {:ok, %__MODULE__{name: name}}
    end
  end

  @doc "Drops a column store and its ETS table."
  @spec drop(t() | atom()) :: :ok | {:error, term()}
  def drop(%__MODULE__{name: name}) do
    # idempotent: the table dies with its owner, so it may already be gone
    if table_exists?(name), do: :ets.delete(name)
    :ok
  end

  def drop(name) when is_atom(name) do
    if table_exists?(name) do
      :ets.delete(name)
      :ok
    else
      {:error, ErrReg.error!("repo.column/not_found")}
    end
  end

  # -- Comn.Repo.Column callbacks --

  @impl Comn.Repo.Column
  def define_schema(%__MODULE__{name: meta}, schema) when is_map(schema) do
    if Enum.all?(schema, fn {k, v} -> is_atom(k) and is_atom(v) end) do
      :ets.insert(meta, {:schema, schema})
      :ok
    else
      {:error, ErrReg.error!("repo.column/invalid_schema")}
    end
  end

  @impl Comn.Repo.Column
  def schema(%__MODULE__{name: meta}) do
    case :ets.lookup(meta, :schema) do
      [{:schema, nil}] ->
        {:error, ErrReg.error!("repo.column/not_found", message: "No schema defined")}

      [{:schema, s}] ->
        {:ok, s}

      [] ->
        {:error, ErrReg.error!("repo.column/not_found")}
    end
  end

  @impl Comn.Repo.Column
  def append_row(%__MODULE__{name: meta} = store, row) when is_map(row) do
    case :ets.lookup(meta, :schema) do
      [{:schema, nil}] ->
        {:error, ErrReg.error!("repo.column/not_found", message: "No schema defined")}

      [{:schema, schema}] ->
        if valid_row?(row, schema) do
          # Buffer in the struct — caller must hold the updated struct
          # For ETS simplicity, we write directly instead of buffering
          id = :ets.update_counter(meta, :next_id, 1)
          :ets.insert(store.name, {id, row})
          :ets.update_counter(meta, :row_count, 1)
          :ok
        else
          {:error, ErrReg.error!("repo.column/schema_mismatch")}
        end
    end
  end

  @impl Comn.Repo.Column
  def append_rows(%__MODULE__{} = store, rows) when is_list(rows) do
    Enum.reduce_while(rows, :ok, fn row, :ok ->
      case append_row(store, row) do
        :ok -> {:cont, :ok}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  @impl Comn.Repo.Column
  def flush(%__MODULE__{name: meta}) do
    # ETS implementation writes directly on append, so flush is a no-op.
    # Return the current row count as "flushed".
    [{:row_count, count}] = :ets.lookup(meta, :row_count)
    {:ok, count}
  end

  @impl Comn.Repo.Column
  def project(%__MODULE__{name: rows} = store, fields, filters)
      when is_list(fields) and is_map(filters) do
    with {:ok, schema} <- defined_schema(store), :ok <- known_fields(schema, fields) do
      rows = for row <- :ets.select(rows, @rows), matches_filters?(row, filters), do: row
      {:ok, Enum.map(rows, &project_row(&1, fields))}
    end
  end

  defp project_row(row, []), do: row
  defp project_row(row, fields), do: Map.take(row, fields)

  defp defined_schema(%__MODULE__{name: meta}) do
    case :ets.lookup(meta, :schema) do
      [{:schema, nil}] ->
        {:error, ErrReg.error!("repo.column/not_found", message: "No schema defined")}

      [{:schema, schema}] ->
        {:ok, schema}
    end
  end

  defp known_fields(schema, fields) do
    case Enum.reject(fields, &Map.has_key?(schema, &1)) do
      [] ->
        :ok

      unknown ->
        {:error,
         ErrReg.error!("repo.column/unknown_column",
           message: "Unknown columns: #{inspect(unknown)}"
         )}
    end
  end

  @impl Comn.Repo.Column
  def count(%__MODULE__{name: t}, filters) when is_map(filters) do
    if filters == %{} do
      [{:row_count, count}] = :ets.lookup(t, :row_count)
      {:ok, count}
    else
      {:ok, Enum.count(:ets.select(t, @rows), &matches_filters?(&1, filters))}
    end
  end

  # -- Comn.Repo callbacks --

  @impl Comn.Repo
  def describe(%__MODULE__{name: name}) do
    [{:schema, schema}] = :ets.lookup(name, :schema)
    [{:row_count, count}] = :ets.lookup(name, :row_count)

    {:ok,
     %{
       name: name,
       schema: schema,
       row_count: count,
       backend: __MODULE__
     }}
  end

  # An event is one row: the headers are the columns, :data is a column.
  @event_schema %{
    id: :string,
    timestamp: :string,
    source: :term,
    type: :atom,
    topic: :string,
    data: :term,
    schema: :string,
    correlation_id: :string,
    request_id: :string,
    version: :integer,
    tags: :list,
    metadata: :map
  }

  @impl Comn.Repo
  def get(%__MODULE__{name: rows}, id: id) do
    case :ets.select(rows, [{{:"$1", %{id: id}}, [{:is_integer, :"$1"}], [:"$_"]}]) do
      [{_rid, row} | _] -> {:ok, struct(Comn.Events.EventStruct, row)}
      [] -> Comn.Repo.not_found(id)
    end
  end

  def get(%__MODULE__{}, _opts) do
    {:error,
     ErrReg.error!("repo.column/query_failed",
       message: "Column stores don't support key-based get; use project/3"
     )}
  end

  @impl Comn.Repo
  def set(%__MODULE__{name: meta} = store, [event: _] = opts) do
    with {:ok, e} <- Comn.Repo.fetch_event(opts) do
      # define the event schema on first use; an existing different schema is a mismatch
      case :ets.lookup(meta, :schema) do
        [{:schema, nil}] -> define_schema(store, @event_schema)
        _ -> :ok
      end

      append_row(store, Map.from_struct(e))
    end
  end

  def set(%__MODULE__{} = store, opts) do
    row = Keyword.fetch!(opts, :value)
    append_row(store, row)
  end

  @impl Comn.Repo
  def delete(%__MODULE__{}, _opts) do
    {:error,
     ErrReg.error!("repo.column/query_failed",
       message: "Column stores are append-only; delete is not supported"
     )}
  end

  @impl Comn.Repo
  def observe(%__MODULE__{name: rows}, opts) do
    rows = :ets.select(rows, @rows)

    if Comn.Repo.events_view?(opts),
      do:
        for(%{id: _, topic: _, data: _} = row <- rows, do: struct(Comn.Events.EventStruct, row)),
      else: rows
  end

  # -- Comn callbacks --

  @impl Comn
  def look, do: "Column.ETS — in-memory column store backed by ETS"

  @impl Comn
  def recon do
    %{
      backend: :ets,
      persistence: :memory,
      type: :implementation
    }
  end

  @impl Comn
  def choices do
    %{types: [":string", ":integer", ":float", ":boolean", ":datetime", ":binary"]}
  end

  @impl Comn
  def act(%{action: :create, name: name}), do: create(name)

  def act(%{action: :project, store: store, fields: fields, filters: filters}),
    do: project(store, fields, filters)

  def act(%{action: :append, store: store, row: row}), do: append_row(store, row)
  def act(%{action: :flush, store: store}), do: flush(store)
  def act(input), do: Comn.unknown_action(input)

  # -- Private helpers --

  defp valid_row?(row, schema) do
    schema_keys = schema |> Map.keys() |> MapSet.new()
    row_keys = row |> Map.keys() |> MapSet.new()
    MapSet.equal?(row_keys, schema_keys)
  end

  defp matches_filters?(row, filters) do
    Enum.all?(filters, fn {key, value} ->
      Map.get(row, key) == value
    end)
  end

  defp table_exists?(name) do
    case :ets.info(name) do
      :undefined -> false
      _ -> true
    end
  end
end
