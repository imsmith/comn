defmodule Comn.Repo.Batch do
  @moduledoc """
  Buffered write-through stores: accumulate, then flush.

  Public, backend-agnostic facade. Callers go through this module; the
  backend is a word in one option to `open/2`. Backends: `:mem` (a
  GenServer buffer linked to the opener). Candidates: Prometheus
  remote_write, Honeycomb, InfluxDB.

  Items are added with `add/2` or `add_many/2` and flushed by size
  threshold, timer, or `flush/1`. `close/1` flushes before releasing so a
  buffer is never silently lost; `drop/1` discards it. The `Comn.Repo`
  forms also work: `set(b, event: e)` buffers the event and
  `observe(b, as: :events)` is the pre-flush snapshot.

  This module also remains the behaviour older backends implement directly;
  `Comn.Repo.Batch.Mem` keeps its public surface.

  ## Examples

      iex> name = String.to_atom("batch_doc_#{:erlang.unique_integer([:positive])}")
      iex> {:ok, b} = Comn.Repo.Batch.open(name, max_size: 10, interval_ms: 0)
      iex> :ok = Comn.Repo.Batch.add(b, %{n: 1})
      iex> {:ok, 1} = Comn.Repo.Batch.pending(b)
      iex> {:ok, 1} = Comn.Repo.Batch.flush(b)
      iex> Comn.Repo.Batch.drop(b)
      :ok
  """

  @behaviour Comn
  @behaviour Comn.Repo

  alias Comn.Repo.{Handle, Lifecycle}

  @typedoc "Opaque batch handle. Treat as a black box."
  @type t :: Handle.t()

  @backends %{mem: Comn.Repo.Batch.MemAdapter}

  @impl Comn.Repo
  def backends, do: @backends

  # ---- behaviour for direct backends (kept for Comn.Repo.Batch.Mem) ----

  @typedoc "A batch store handle — typically a named process or pid."
  @type store :: atom() | pid()

  @typedoc "A single item to buffer. Structure is backend-specific."
  @type item :: term()

  @typedoc """
  Flush strategy configuration.

  - `:max_size` — flush when buffer reaches this count (default: 1000)
  - `:interval_ms` — flush on this interval in milliseconds (default: 5000)
  - `:on_flush` — callback function invoked with the batch list on flush
  """
  @type flush_opts :: keyword()

  @doc """
  Adds a single item to the batch buffer.

  May trigger an auto-flush if the buffer reaches `:max_size`.

  Errors: `repo.batch/buffer_full` (if a hard limit is enforced).
  """
  @callback add(store(), item()) :: :ok | {:error, term()}

  @doc """
  Adds multiple items to the batch buffer.

  More efficient than calling `add/2` in a loop. May trigger auto-flush.

  Errors: `repo.batch/buffer_full`.
  """
  @callback add_many(store(), [item()]) :: :ok | {:error, term()}

  @doc """
  Flushes the buffer to the backend immediately.

  Returns the number of items flushed. The buffer is empty after this call.

  Errors: `repo.batch/flush_failed`.
  """
  @callback flush(store()) :: {:ok, non_neg_integer()} | {:error, term()}

  @doc """
  Returns the number of items currently buffered (not yet flushed).
  """
  @callback pending(store()) :: {:ok, non_neg_integer()}

  @doc """
  Returns the current flush configuration.
  """
  @callback config(store()) :: {:ok, map()}

  # ---- lifecycle ----

  @doc """
  Opens a batch buffer.

  Options: `:backend` — `:mem` (default) or a module implementing the private
  backend contract; `:max_size`, `:interval_ms`, `:on_flush` (see
  `t:flush_opts/0`). The rest go to the backend.

  Errors: `repo.batch/invalid_opts`.
  """
  @spec open(atom(), keyword()) :: {:ok, t()} | {:error, Comn.Errors.ErrorStruct.t()}
  def open(name, opts \\ []) when is_atom(name) and is_list(opts),
    do: Lifecycle.open(__MODULE__, name, Keyword.put_new(opts, :backend, :mem))

  @doc "Flushes pending items, then releases the handle. Idempotent."
  @spec close(t()) :: :ok
  def close(%Handle{} = h), do: Lifecycle.close(h)

  @doc "Releases the handle and discards pending items. Idempotent."
  @spec drop(t()) :: :ok
  def drop(%Handle{} = h), do: Lifecycle.drop(h)

  # ---- batch verbs ----

  @doc "Buffers one item; may trigger an auto-flush. Errors: `repo.batch/buffer_full`."
  @spec add(t(), item()) :: :ok | {:error, Comn.Errors.ErrorStruct.t()}
  def add(%Handle{backend: b, state: s}, item), do: b.add(s, item)

  @doc "Buffers many items at once. Errors: `repo.batch/buffer_full`."
  @spec add_many(t(), [item()]) :: :ok | {:error, Comn.Errors.ErrorStruct.t()}
  def add_many(%Handle{backend: b, state: s}, items) when is_list(items), do: b.add_many(s, items)

  @doc "Flushes now. Returns the number of items flushed. Errors: `repo.batch/flush_failed`."
  @spec flush(t()) :: {:ok, non_neg_integer()} | {:error, Comn.Errors.ErrorStruct.t()}
  def flush(%Handle{backend: b, state: s}), do: b.flush(s)

  @doc "Number of items buffered and not yet flushed."
  @spec pending(t()) :: {:ok, non_neg_integer()}
  def pending(%Handle{backend: b, state: s}), do: b.pending(s)

  @doc "The flush configuration in force."
  @spec config(t()) :: {:ok, map()}
  def config(%Handle{backend: b, state: s}), do: b.config(s)

  # ---- @behaviour Comn.Repo ----

  @impl Comn.Repo
  def describe(%Handle{backend: b, state: s}), do: b.describe(s)

  @doc "Batches are write-only: only `get(b, id: event_id)` over the pending buffer is meaningful."
  @impl Comn.Repo
  def get(%Handle{backend: b, state: s}, opts), do: b.get(s, opts)

  @doc "`set(b, event: e)` buffers the event; `set(b, value: item)` buffers an item."
  @impl Comn.Repo
  def set(%Handle{backend: b, state: s}, opts), do: b.set(s, opts)

  @impl Comn.Repo
  def delete(%Handle{backend: b, state: s}, opts), do: b.delete(s, opts)

  @impl Comn.Repo
  def observe(%Handle{backend: b, state: s}, opts \\ []), do: b.observe(s, opts)

  # ---- @behaviour Comn ----

  @impl Comn
  def look, do: "Batch — buffered write-through with configurable flush strategy"

  @impl Comn
  def recon do
    %{
      callbacks: [:open, :close, :drop, :add, :add_many, :flush, :pending, :config],
      backends: Map.keys(@backends),
      extends: Comn.Repo,
      type: :facade
    }
  end

  @impl Comn
  def choices, do: %{backends: ["mem"]}

  @impl Comn
  def act(%{action: :open, name: n, opts: o}), do: open(n, o)
  def act(%{action: :open, name: n}), do: open(n, [])
  def act(input), do: Comn.unknown_action(input)
end
