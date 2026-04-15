defmodule Comn.Repo.Batch do
  @moduledoc """
  Behaviour for buffered write-through stores.

  Extends `Comn.Repo` with an accumulate-then-flush pattern. Items are
  added to a buffer; the buffer is flushed to the backend when triggered
  by the caller, a size threshold, or a time interval.

  Batch stores are write-biased — you may never read back from them.
  Typical backends: Prometheus remote_write, Honeycomb, InfluxDB, DataDog.

  A backend like ClickHouse can implement both `Comn.Repo.Column` (for
  queries) and `Comn.Repo.Batch` (for buffered ingestion).

  Also implements `@behaviour Comn` for uniform introspection.

  ## Lifecycle

  1. Start the batch process with a flush strategy (`start_link/1`)
  2. Add items (`add/2` or `add_many/2`)
  3. Items flush automatically at threshold, or manually via `flush/1`
  4. Check buffer state with `pending/1`

  ## Mapping to Comn.Repo

  - `describe/1` — buffer size, flush config, backend metadata
  - `get/2` — not idiomatic; batch is write-only. Returns error.
  - `set/2` — delegates to `add/2`
  - `delete/2` — not supported
  - `observe/2` — returns current buffer contents (pre-flush snapshot)

  ## Examples

      iex> Comn.Repo.Batch.look()
      "Batch — buffered write-through with configurable flush strategy"

      iex> %{extends: Comn.Repo} = Comn.Repo.Batch.recon()
  """

  @behaviour Comn

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

  # Comn callbacks

  @impl Comn
  def look, do: "Batch — buffered write-through with configurable flush strategy"

  @impl Comn
  def recon do
    %{
      callbacks: [:add, :add_many, :flush, :pending, :config],
      extends: Comn.Repo,
      type: :behaviour
    }
  end

  @impl Comn
  def choices do
    %{implementations: ["Mem"]}
  end

  @impl Comn
  def act(_input), do: {:error, :behaviour_only}
end
