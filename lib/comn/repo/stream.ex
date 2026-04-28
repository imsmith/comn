defmodule Comn.Repo.Stream do
  @moduledoc """
  Behaviour for append-only, replayable event streams.

  Extends `Comn.Repo` with a Kafka-style log abstraction: events are
  appended in monotonic order, and consumers read at their own offsets,
  replaying the log from any point. Unlike `Comn.Repo.Queue`, there is
  no per-consumer dequeue and no acknowledgement — the stream is the
  durable record, consumers track their own positions.

  Stream events are `Comn.Events.EventStruct`. Offsets are opaque per
  backend (typically integers, but also valid: byte offsets, Kafka
  partition+offset tuples, NATS sequence numbers). The only canonical
  accessors are `head/1` (latest offset) and `tail/1` (earliest offset).

  Caller-tracked offsets in v1: callers pass the offset they want to
  read from on each call. Durable consumer groups (where the backend
  remembers per-consumer offsets) are out of scope here.

  Also implements `@behaviour Comn` for uniform introspection.

  ## Mapping to Comn.Repo

  - `describe/1` — stream metadata (name, head, tail, count)
  - `get/2` — `[offset: o]` reads a single event at offset
  - `set/2` — delegates to `append/2`; `[event: e]` is the canonical form
  - `delete/2` — **not supported**; streams are append-only
  - `observe/2` — returns a Stream of `{offset, event}` from `:head`

  ## Examples

      iex> Comn.Repo.Stream.look()
      "Stream — append-only, replayable event log with caller-tracked offsets"

      iex> %{extends: Comn.Repo} = Comn.Repo.Stream.recon()
  """

  @behaviour Comn

  @typedoc "A stream handle — a named atom in v1."
  @type stream :: atom()

  @typedoc "An opaque, monotonic offset within a stream."
  @type offset :: term()

  @typedoc """
  A read cursor: an explicit offset, `:head` (latest), or `:tail` (earliest).

  When reading from `:tail` with count N, returns the **last** N events
  (i.e. ending at head). When reading from an explicit offset, returns
  events at and after that offset.
  """
  @type cursor :: offset() | :head | :tail

  @doc """
  Appends an event to the stream's head.

  Returns the new offset.

  Errors: `repo.stream/not_found`, `repo.stream/invalid_event`.
  """
  @callback append(stream(), Comn.Events.EventStruct.t()) :: {:ok, offset()} | {:error, term()}

  @doc """
  Appends multiple events. Returns offsets in the same order as input.

  Errors: `repo.stream/not_found`, `repo.stream/invalid_event`.
  """
  @callback append_many(stream(), [Comn.Events.EventStruct.t()]) ::
              {:ok, [offset()]} | {:error, term()}

  @doc """
  Reads up to `count` events starting from the cursor.

  Returns `{:ok, [{offset, event}, ...]}` with up to `count` entries.
  Fewer entries are returned if the stream has insufficient events.

  Errors: `repo.stream/not_found`, `repo.stream/invalid_offset`.
  """
  @callback read(stream(), cursor(), pos_integer()) ::
              {:ok, [{offset(), Comn.Events.EventStruct.t()}]} | {:error, term()}

  @doc """
  Returns the latest (most-recently-appended) offset, or `nil` if empty.

  Errors: `repo.stream/not_found`.
  """
  @callback head(stream()) :: {:ok, offset() | nil} | {:error, term()}

  @doc """
  Returns the earliest (oldest-retained) offset, or `nil` if empty.

  Errors: `repo.stream/not_found`.
  """
  @callback tail(stream()) :: {:ok, offset() | nil} | {:error, term()}

  # Comn callbacks

  @impl Comn
  def look, do: "Stream — append-only, replayable event log with caller-tracked offsets"

  @impl Comn
  def recon do
    %{
      callbacks: [:append, :append_many, :read, :head, :tail],
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
