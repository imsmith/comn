defmodule Comn.Repo.Column do
  @moduledoc """
  Column-oriented stores: schema-aware, append-heavy, projection-queryable.

  Public, backend-agnostic facade. Callers go through this module; the
  backend is a word in one option to `open/2`. Backends: `:ets` (in-memory,
  dies with its owner). Candidates: ClickHouse, DuckDB, Parquet, BigQuery.

  Column stores select *columns* across many rows rather than fetching
  complete rows by key, so the verbs are `define_schema/2`, `append_row/2`,
  `append_rows/2`, `flush/1`, `project/3`, and `count/2`. The `Comn.Repo`
  forms also work: `set(c, event: e)` appends an event as a row and
  `observe(c, as: :events)` reads them back.

  This module also remains the behaviour older backends implement directly;
  `Comn.Repo.Column.ETS` keeps its public surface.

  ## Examples

      iex> name = String.to_atom("col_doc_#{:erlang.unique_integer([:positive])}")
      iex> {:ok, c} = Comn.Repo.Column.open(name, schema: %{host: :string, cpu: :float})
      iex> :ok = Comn.Repo.Column.append_row(c, %{host: "web-1", cpu: 0.5})
      iex> {:ok, [%{host: "web-1"}]} = Comn.Repo.Column.project(c, [:host], %{})
      iex> Comn.Repo.Column.drop(c)
      :ok
  """

  @behaviour Comn
  @behaviour Comn.Repo

  alias Comn.Repo.{Handle, Lifecycle}

  @typedoc "Opaque column-store handle. Treat as a black box."
  @type t :: Handle.t()

  @backends %{ets: Comn.Repo.Column.ETSAdapter}

  @impl Comn.Repo
  def backends, do: @backends

  # ---- behaviour for direct backends (kept for Comn.Repo.Column.ETS) ----

  @typedoc """
  A column store resource — handle to a dataset, table reference, or
  connection + table name. Backend-specific.
  """
  @type store :: term()

  @typedoc "A schema definition — map of column names to types."
  @type schema :: %{atom() => atom()}

  @typedoc "A row — map of column names to values."
  @type row :: %{atom() => term()}

  @typedoc "A filter expression — map of column names to match values or filter tuples."
  @type filters :: %{atom() => term()}

  @doc """
  Defines or updates the schema for a column store.

  The schema maps column names to type atoms (e.g. `:string`, `:integer`,
  `:float`, `:boolean`, `:datetime`, `:binary`).

  Errors: `repo.column/invalid_schema`.
  """
  @callback define_schema(store(), schema()) :: :ok | {:error, term()}

  @doc """
  Returns the current schema for a column store.

  Errors: `repo.column/not_found`.
  """
  @callback schema(store()) :: {:ok, schema()} | {:error, term()}

  @doc """
  Appends a single row to the column store's write buffer.

  The row must conform to the defined schema. Rows are buffered until
  `flush/1` is called (or the backend auto-flushes at a threshold).

  Errors: `repo.column/schema_mismatch`, `repo.column/not_found`.
  """
  @callback append_row(store(), row()) :: :ok | {:error, term()}

  @doc """
  Appends multiple rows to the column store's write buffer.

  More efficient than calling `append_row/2` in a loop — backends can
  optimize for batch insertion.

  Errors: `repo.column/schema_mismatch`, `repo.column/not_found`.
  """
  @callback append_rows(store(), [row()]) :: :ok | {:error, term()}

  @doc """
  Flushes the write buffer to persistent storage.

  Returns the number of rows flushed.

  Errors: `repo.column/flush_failed`.
  """
  @callback flush(store()) :: {:ok, non_neg_integer()} | {:error, term()}

  @doc """
  Queries the store by projecting specific columns with optional filters.

  `fields` is a list of column names to select. An empty list means all columns.
  `filters` is a map of column names to match values or filter expressions.

  Returns a list of row maps containing only the requested columns.

  Errors: `repo.column/unknown_column`, `repo.column/query_failed`.
  """
  @callback project(store(), fields :: [atom()], filters()) :: {:ok, [row()]} | {:error, term()}

  @doc """
  Returns the row count for the store, optionally filtered.

  Errors: `repo.column/not_found`.
  """
  @callback count(store(), filters()) :: {:ok, non_neg_integer()} | {:error, term()}

  # ---- lifecycle ----

  @doc """
  Opens a column store.

  Options: `:backend` — `:ets` (default) or a module implementing the private
  backend contract; `:schema` — defined on open when given. The rest go to
  the backend.

  Errors: `repo.column/invalid_opts`, `repo.column/already_exists`.
  """
  @spec open(atom(), keyword()) :: {:ok, t()} | {:error, Comn.Errors.ErrorStruct.t()}
  def open(name, opts \\ []) when is_atom(name) and is_list(opts),
    do: Lifecycle.open(__MODULE__, name, Keyword.put_new(opts, :backend, :ets))

  @doc "Releases the handle. A durable backend keeps its rows. Idempotent."
  @spec close(t()) :: :ok
  def close(%Handle{} = h), do: Lifecycle.close(h)

  @doc "Deletes the store and its rows. Idempotent."
  @spec drop(t()) :: :ok
  def drop(%Handle{} = h), do: Lifecycle.drop(h)

  # ---- column verbs ----

  @doc "Defines or replaces the schema. Errors: `repo.column/invalid_schema`."
  @spec define_schema(t(), schema()) :: :ok | {:error, Comn.Errors.ErrorStruct.t()}
  def define_schema(%Handle{backend: b, state: s}, schema), do: b.define_schema(s, schema)

  @doc "The current schema. Errors: `repo.column/not_found`."
  @spec schema(t()) :: {:ok, schema()} | {:error, Comn.Errors.ErrorStruct.t()}
  def schema(%Handle{backend: b, state: s}), do: b.schema(s)

  @doc "Appends one row. Errors: `repo.column/schema_mismatch`, `repo.column/not_found`."
  @spec append_row(t(), row()) :: :ok | {:error, Comn.Errors.ErrorStruct.t()}
  def append_row(%Handle{backend: b, state: s}, row), do: b.append_row(s, row)

  @doc "Appends many rows; stops at the first failure."
  @spec append_rows(t(), [row()]) :: :ok | {:error, Comn.Errors.ErrorStruct.t()}
  def append_rows(%Handle{backend: b, state: s}, rows), do: b.append_rows(s, rows)

  @doc "Flushes buffered rows. Returns the row count flushed. Errors: `repo.column/flush_failed`."
  @spec flush(t()) :: {:ok, non_neg_integer()} | {:error, Comn.Errors.ErrorStruct.t()}
  def flush(%Handle{backend: b, state: s}), do: b.flush(s)

  @doc "Projects `fields` (empty list for all) over rows matching `filters`. Errors: `repo.column/unknown_column`."
  @spec project(t(), [atom()], filters()) ::
          {:ok, [row()]} | {:error, Comn.Errors.ErrorStruct.t()}
  def project(%Handle{backend: b, state: s}, fields, filters \\ %{}),
    do: b.project(s, fields, filters)

  @doc "Row count, optionally filtered."
  @spec count(t(), filters()) :: {:ok, non_neg_integer()} | {:error, Comn.Errors.ErrorStruct.t()}
  def count(%Handle{backend: b, state: s}, filters \\ %{}), do: b.count(s, filters)

  # ---- @behaviour Comn.Repo ----

  @impl Comn.Repo
  def describe(%Handle{backend: b, state: s}), do: b.describe(s)

  @doc "Column stores are not keyed: only `get(c, id: event_id)` is meaningful."
  @impl Comn.Repo
  def get(%Handle{backend: b, state: s}, opts), do: b.get(s, opts)

  @doc "`set(c, event: e)` appends the event as a row; `set(c, value: row)` appends a row."
  @impl Comn.Repo
  def set(%Handle{backend: b, state: s}, opts), do: b.set(s, opts)

  @impl Comn.Repo
  def delete(%Handle{backend: b, state: s}, opts), do: b.delete(s, opts)

  @impl Comn.Repo
  def observe(%Handle{backend: b, state: s}, opts \\ []), do: b.observe(s, opts)

  # ---- @behaviour Comn ----

  @impl Comn
  def look, do: "Column — schema-aware projection queries over appendable column stores"

  @impl Comn
  def recon do
    %{
      callbacks: [
        :open,
        :close,
        :drop,
        :define_schema,
        :schema,
        :append_row,
        :append_rows,
        :flush,
        :project,
        :count
      ],
      backends: Map.keys(@backends),
      extends: Comn.Repo,
      type: :facade
    }
  end

  @impl Comn
  def choices, do: %{backends: ["ets"]}

  @impl Comn
  def act(%{action: :open, name: n, opts: o}), do: open(n, o)
  def act(%{action: :open, name: n}), do: open(n, [])
  def act(input), do: Comn.unknown_action(input)
end
