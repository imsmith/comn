defmodule Comn.Repo.Column do
  @moduledoc """
  Behaviour for column-oriented data stores.

  Extends `Comn.Repo` with operations optimized for append-heavy, schema-aware,
  projection-queryable datasets. Column stores are fundamentally different from
  row-oriented tables — they optimize for selecting *columns* across many rows
  rather than fetching complete rows by key.

  Backends: ClickHouse, DuckDB, Parquet files, BigQuery, DeltaLake.

  Also implements `@behaviour Comn` for uniform introspection.

  ## Lifecycle

  1. Define a schema (`define_schema/2`)
  2. Append rows (`append_row/2` or `append_rows/2`)
  3. Flush buffered rows to storage (`flush/1`)
  4. Query by selecting columns with optional filters (`project/3`)

  ## Mapping to Comn.Repo

  Column stores don't map cleanly to all base Repo verbs:

  - `describe/1` — returns schema, row count, storage metadata
  - `get/2` — not idiomatic; column stores aren't keyed. Use `project/3`
  - `set/2` — not idiomatic; use `append_row/2`
  - `delete/2` — expensive or unsupported on most backends
  - `observe/2` — stream of rows or change feed

  ## Examples

      iex> Comn.Repo.Column.look()
      "Column — schema-aware projection queries over appendable column stores"

      iex> %{extends: Comn.Repo} = Comn.Repo.Column.recon()
  """

  @behaviour Comn

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

  # Comn callbacks

  @impl Comn
  def look, do: "Column — schema-aware projection queries over appendable column stores"

  @impl Comn
  def recon do
    %{
      callbacks: [:define_schema, :schema, :append_row, :append_rows, :flush, :project, :count],
      extends: Comn.Repo,
      type: :behaviour
    }
  end

  @impl Comn
  def choices do
    %{implementations: ["ETS"]}
  end

  @impl Comn
  def act(_input), do: {:error, :behaviour_only}
end
