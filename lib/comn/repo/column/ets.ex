defmodule Comn.Repo.Column.ETS do
  @moduledoc """
  ETS-backed implementation of `Comn.Repo.Column` and `Comn.Repo`.

  In-memory column store using two ETS tables per store: one for rows
  (ordered_set for insertion order) and one for metadata (schema, counters).
  Rows are buffered in-process until `flush/1` writes them to ETS.

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

  @enforce_keys [:name, :rows_table, :meta_table]
  defstruct [:name, :rows_table, :meta_table, buffer: []]

  @type t :: %__MODULE__{
          name: atom(),
          rows_table: atom(),
          meta_table: atom(),
          buffer: [map()]
        }

  # -- Lifecycle --

  @doc "Creates a new column store. Returns a store handle."
  @spec create(atom()) :: {:ok, t()} | {:error, term()}
  def create(name) when is_atom(name) do
    rows_table = :"#{name}_rows"
    meta_table = :"#{name}_meta"

    if table_exists?(rows_table) do
      {:error,
       ErrReg.error!("repo.column/not_found",
         message: "Column store #{name} already exists"
       )}
    else
      :ets.new(rows_table, [:named_table, :public, :ordered_set])
      :ets.new(meta_table, [:named_table, :public, :set])
      :ets.insert(meta_table, {:schema, nil})
      :ets.insert(meta_table, {:row_count, 0})
      :ets.insert(meta_table, {:next_id, 0})

      {:ok, %__MODULE__{name: name, rows_table: rows_table, meta_table: meta_table}}
    end
  end

  @doc "Drops a column store and its ETS tables."
  @spec drop(t() | atom()) :: :ok | {:error, term()}
  def drop(%__MODULE__{rows_table: rows, meta_table: meta}) do
    # idempotent: the tables die with their owner, so they may already be gone
    if table_exists?(rows), do: :ets.delete(rows)
    if table_exists?(meta), do: :ets.delete(meta)
    :ok
  end

  def drop(name) when is_atom(name) do
    rows_table = :"#{name}_rows"

    if table_exists?(rows_table) do
      :ets.delete(rows_table)
      :ets.delete(:"#{name}_meta")
      :ok
    else
      {:error, ErrReg.error!("repo.column/not_found")}
    end
  end

  # -- Comn.Repo.Column callbacks --

  @impl Comn.Repo.Column
  def define_schema(%__MODULE__{meta_table: meta} = _store, schema) when is_map(schema) do
    if Enum.all?(schema, fn {k, v} -> is_atom(k) and is_atom(v) end) do
      :ets.insert(meta, {:schema, schema})
      :ok
    else
      {:error, ErrReg.error!("repo.column/invalid_schema")}
    end
  end

  @impl Comn.Repo.Column
  def schema(%__MODULE__{meta_table: meta}) do
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
  def append_row(%__MODULE__{meta_table: meta} = store, row) when is_map(row) do
    case :ets.lookup(meta, :schema) do
      [{:schema, nil}] ->
        {:error, ErrReg.error!("repo.column/not_found", message: "No schema defined")}

      [{:schema, schema}] ->
        if valid_row?(row, schema) do
          # Buffer in the struct — caller must hold the updated struct
          # For ETS simplicity, we write directly instead of buffering
          id = :ets.update_counter(meta, :next_id, 1)
          :ets.insert(store.rows_table, {id, row})
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
  def flush(%__MODULE__{meta_table: meta}) do
    # ETS implementation writes directly on append, so flush is a no-op.
    # Return the current row count as "flushed".
    [{:row_count, count}] = :ets.lookup(meta, :row_count)
    {:ok, count}
  end

  @impl Comn.Repo.Column
  def project(%__MODULE__{rows_table: rows, meta_table: meta}, fields, filters)
      when is_list(fields) and is_map(filters) do
    case :ets.lookup(meta, :schema) do
      [{:schema, nil}] ->
        {:error, ErrReg.error!("repo.column/not_found", message: "No schema defined")}

      [{:schema, schema}] ->
        # Validate requested fields exist in schema
        unknown = Enum.reject(fields, &Map.has_key?(schema, &1))

        if unknown != [] do
          {:error,
           ErrReg.error!("repo.column/unknown_column",
             message: "Unknown columns: #{inspect(unknown)}"
           )}
        else
          folded =
            :ets.foldl(
              fn {_id, row}, acc ->
                if matches_filters?(row, filters) do
                  projected = if fields == [], do: row, else: Map.take(row, fields)
                  [projected | acc]
                else
                  acc
                end
              end,
              [],
              rows
            )

          {:ok, Enum.reverse(folded)}
        end
    end
  end

  @impl Comn.Repo.Column
  def count(%__MODULE__{meta_table: meta, rows_table: rows}, filters) when is_map(filters) do
    if filters == %{} do
      [{:row_count, count}] = :ets.lookup(meta, :row_count)
      {:ok, count}
    else
      count =
        :ets.foldl(
          fn {_id, row}, acc ->
            if matches_filters?(row, filters), do: acc + 1, else: acc
          end,
          0,
          rows
        )

      {:ok, count}
    end
  end

  # -- Comn.Repo callbacks --

  @impl Comn.Repo
  def describe(%__MODULE__{name: name, meta_table: meta}) do
    [{:schema, schema}] = :ets.lookup(meta, :schema)
    [{:row_count, count}] = :ets.lookup(meta, :row_count)

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
  def get(%__MODULE__{rows_table: rows}, id: id) do
    case :ets.select(rows, [{{:_, %{id: id}}, [], [:"$_"]}]) do
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
  def set(%__MODULE__{meta_table: meta} = store, [event: _] = opts) do
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
  def observe(%__MODULE__{rows_table: rows}, opts) do
    rows = rows |> :ets.tab2list() |> Enum.sort_by(&elem(&1, 0)) |> Enum.map(&elem(&1, 1))

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
