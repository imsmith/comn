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

  Offsets are caller-tracked by default: callers pass the offset they
  want to read from on each call. Backends may also remember how far a
  named consumer group has processed via the optional `commit/3` and
  `position/2`; see "Consumer groups" below.

  ## Live subscribe

  Backends may implement the optional `subscribe/2` and `unsubscribe/2`.
  A subscriber receives `{:stream, name, offset, event}` for every event
  appended after it subscribed. There is no replay option: to catch up,
  subscribe first, then `read/3` from the last offset you processed and
  drop any live message whose offset you have already seen.

  ## Consumer groups

  Backends may implement the optional `commit/3` and `position/2`. A
  group is any term; the backend stores one offset per group per stream.
  There is no membership or rebalancing, only the bookmark. A consumer
  loop is: `position/2`, `read/3` from the offset after it (or `:head`
  when nil), process, `commit/3`, repeat.

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
  A read cursor: an explicit offset, `:head`, or `:tail`.

  The two atoms follow Unix `head`/`tail`: `read(s, :head, n)` returns
  the **first** n events, `read(s, :tail, n)` the **last** n. Note this is
  the opposite end from `head/1` (latest offset) and `tail/1` (earliest),
  which follow log terminology. An explicit offset reads forward from
  that offset inclusive.
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

  @doc """
  Subscribes the calling process to live appends.

  Returns an opaque reference for `unsubscribe/2`. The subscription ends
  automatically when the subscriber exits. Delivery is a plain message
  `{:stream, name, offset, event}`.

  Errors: `repo.stream/not_found`.
  """
  @callback subscribe(stream(), keyword()) :: {:ok, reference()} | {:error, term()}

  @doc "Cancels a subscription made by `subscribe/2`."
  @callback unsubscribe(stream(), reference()) :: :ok

  @doc """
  Records that `group` has processed through `offset`. Later commits
  overwrite earlier ones.

  Errors: `repo.stream/not_found`, `repo.stream/invalid_offset` (offset
  was never issued by this stream).
  """
  @callback commit(stream(), group :: term(), offset()) :: :ok | {:error, term()}

  @doc """
  Returns the last committed offset for `group`, or `nil` if it has
  never committed.

  Errors: `repo.stream/not_found`.
  """
  @callback position(stream(), group :: term()) :: {:ok, offset() | nil} | {:error, term()}

  @optional_callbacks subscribe: 2, unsubscribe: 2, commit: 3, position: 2

  # Comn callbacks

  @impl Comn
  def look, do: "Stream — append-only, replayable event log with caller-tracked offsets"

  @impl Comn
  def recon do
    %{
      callbacks: [
        :append,
        :append_many,
        :read,
        :head,
        :tail,
        :subscribe,
        :unsubscribe,
        :commit,
        :position
      ],
      extends: Comn.Repo,
      type: :behaviour
    }
  end

  @impl Comn
  def choices do
    %{implementations: ["Mem", "SQLite"]}
  end

  @impl Comn
  def act(_input), do: Comn.behaviour_only()
end
