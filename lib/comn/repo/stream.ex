defmodule Comn.Repo.Stream do
  @moduledoc """
  Append-only, replayable event log.

  Public, backend-agnostic facade. Callers always go through this module;
  backends (`:mem`, `:sqlite`, `:jetstream`) are private and selected via
  the `:backend` option to `open/2`. The same code works on any backend.

  Events are `Comn.Events.EventStruct`. Offsets are opaque per backend
  (integers starting at 1 on every shipped backend; JetStream's are its
  stream sequence). Consumers track their own offsets.

  ## Read cursors

  `read(h, :head, n)` returns the **first** n events, `read(h, :tail, n)`
  the **last** n, following Unix `head`/`tail`. An explicit offset reads
  forward from that offset inclusive. `head/1` and `tail/1` follow log
  terminology instead: latest and earliest offset.

  ## Live subscribe

  `subscribe/2` delivers `{:stream, name, offset, event}` to the calling
  process for every event appended afterwards. No replay: subscribe first,
  then `read/3` from the last offset you processed and drop live messages
  whose offset you have already seen.

  ## Lifecycle

  `open/2` creates or reopens; `close/1` releases the handle (a durable
  backend keeps its data); `drop/1` deletes the stream. For a supervised
  durable stream use the child spec:
  `{Comn.Repo.Stream, name: :audit, backend: :sqlite, path: "/var/lib/app/audit.db"}`.

  ## Examples

      iex> name = String.to_atom("stream_doc_#{:erlang.unique_integer([:positive])}")
      iex> {:ok, s} = Comn.Repo.Stream.open(name, backend: :mem)
      iex> event = Comn.Events.EventStruct.new(:test, "doc.example", %{})
      iex> {:ok, offset} = Comn.Repo.Stream.append(s, event)
      iex> {:ok, ^offset} = Comn.Repo.Stream.head(s)
      iex> {:ok, [{^offset, ^event}]} = Comn.Repo.Stream.read(s, :head, 10)
      iex> Comn.Repo.Stream.drop(s)
      :ok

  Live delivery:

      iex> name = String.to_atom("stream_live_#{:erlang.unique_integer([:positive])}")
      iex> {:ok, s} = Comn.Repo.Stream.open(name, backend: :mem)
      iex> {:ok, ref} = Comn.Repo.Stream.subscribe(s, [])
      iex> {:ok, offset} = Comn.Repo.Stream.append(s, Comn.Events.EventStruct.new(:test, "doc.live", %{}))
      iex> receive do
      ...>   {:stream, ^name, ^offset, %Comn.Events.EventStruct{topic: topic}} -> topic
      ...> end
      "doc.live"
      iex> :ok = Comn.Repo.Stream.unsubscribe(s, ref)
      iex> Comn.Repo.Stream.drop(s)
      :ok
  """

  @behaviour Comn
  @behaviour Comn.Repo

  alias Comn.Errors.Registry, as: ErrReg
  alias Comn.Events.EventStruct
  alias Comn.Repo.Stream.Handle

  @typedoc "Opaque stream handle. Treat as a black box."
  @type t :: Handle.t()

  @typedoc "An opaque, monotonic offset within a stream."
  @type offset :: term()

  @typedoc "A read cursor: an explicit offset, `:head` (first n) or `:tail` (last n)."
  @type cursor :: offset() | :head | :tail

  @backends %{
    mem: Comn.Repo.Stream.Mem,
    sqlite: Comn.Repo.Stream.SQLite,
    jetstream: Comn.Repo.Stream.JetStream
  }

  # Subscribers live in the shared Comn.EventBus registry under {:stream, name}.
  @registry Comn.EventBus

  # ---- lifecycle ----

  @doc """
  Opens a stream.

  Options:

    * `:backend` — `:mem` (default), `:sqlite`, `:jetstream`, or a module
      implementing the private backend contract.
    * `:path` — required for `:sqlite`; absolute path to the file.
    * `:conn` — required for `:jetstream`; a `Gnat` connection name or pid.

  All other options are passed to the backend.

  Errors: `repo.stream/invalid_opts`, `repo.stream/already_exists`,
  `repo.stream/backend_error`.
  """
  @spec open(atom(), keyword()) :: {:ok, t()} | {:error, Comn.Errors.ErrorStruct.t()}
  def open(name, opts \\ []) when is_atom(name) and is_list(opts) do
    with {:ok, backend} <- resolve_backend(Keyword.get(opts, :backend, :mem)),
         {:ok, state} <- backend.open(name, opts) do
      {:ok, %Handle{backend: backend, state: state, name: name}}
    end
  end

  @doc "Releases the handle. A durable backend keeps its data. Idempotent."
  @spec close(t()) :: :ok
  def close(%Handle{backend: b, state: s}), do: b.close(s)

  @doc "Deletes the stream and everything in it. Idempotent."
  @spec drop(t()) :: :ok
  def drop(%Handle{backend: b, state: s}), do: b.drop(s)

  @doc "Child spec for a supervised stream: `{Comn.Repo.Stream, name: n, backend: :sqlite, path: p}`."
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    {:ok, backend} = resolve_backend(Keyword.get(opts, :backend, :mem))
    %{id: {__MODULE__, Keyword.fetch!(opts, :name)}, start: {backend, :start_link, [opts]}}
  end

  # ---- log verbs ----

  @doc "Appends one event. Returns its offset. Errors: `repo.stream/invalid_event`."
  @spec append(t(), EventStruct.t()) :: {:ok, offset()} | {:error, Comn.Errors.ErrorStruct.t()}
  def append(%Handle{} = h, %EventStruct{} = event) do
    with {:ok, [offset]} <- append_many(h, [event]), do: {:ok, offset}
  end

  def append(%Handle{}, _not_event), do: {:error, ErrReg.error!("repo.stream/invalid_event")}

  @doc "Appends many events. Offsets come back in input order; nothing is appended if any event is invalid."
  @spec append_many(t(), [EventStruct.t()]) ::
          {:ok, [offset()]} | {:error, Comn.Errors.ErrorStruct.t()}
  def append_many(%Handle{backend: b, state: s}, events) when is_list(events) do
    if Enum.all?(events, &match?(%EventStruct{}, &1)),
      do: b.append(s, events),
      else: {:error, ErrReg.error!("repo.stream/invalid_event")}
  end

  @doc "Reads up to `count` events from the cursor as `{offset, event}` pairs. Errors: `repo.stream/invalid_offset`."
  @spec read(t(), cursor(), pos_integer()) ::
          {:ok, [{offset(), EventStruct.t()}]} | {:error, Comn.Errors.ErrorStruct.t()}
  def read(%Handle{backend: b, state: s}, cursor, count) when is_integer(count) and count > 0 do
    b.read(s, cursor, count)
  end

  @doc "Latest offset, or nil when empty."
  @spec head(t()) :: {:ok, offset() | nil} | {:error, Comn.Errors.ErrorStruct.t()}
  def head(%Handle{backend: b, state: s}), do: b.head(s)

  @doc "Earliest retained offset, or nil when empty."
  @spec tail(t()) :: {:ok, offset() | nil} | {:error, Comn.Errors.ErrorStruct.t()}
  def tail(%Handle{backend: b, state: s}), do: b.tail(s)

  # ---- live subscribe ----

  @doc """
  Subscribes the calling process to live appends; it receives
  `{:stream, name, offset, event}`. Returns a reference for `unsubscribe/2`.
  The subscription ends when the subscriber exits.
  """
  @spec subscribe(t(), keyword()) :: {:ok, reference()} | {:error, Comn.Errors.ErrorStruct.t()}
  def subscribe(%Handle{backend: b, state: s, name: name}, _opts \\ []) do
    ref = make_ref()

    with {:ok, _owner} <- Registry.register(@registry, {:stream, name}, ref),
         :ok <- b.subscribe(s) do
      {:ok, ref}
    end
  end

  @doc "Cancels a subscription made by `subscribe/2`."
  @spec unsubscribe(t(), reference()) :: :ok
  def unsubscribe(%Handle{name: name}, ref) when is_reference(ref) do
    Registry.unregister_match(@registry, {:stream, name}, ref)
  end

  @doc false
  # Called by backends for every appended event.
  def notify(name, offset, event) do
    Registry.dispatch(@registry, {:stream, name}, fn entries ->
      for {pid, _ref} <- entries, do: send(pid, {:stream, name, offset, event})
    end)
  end

  # ---- @behaviour Comn.Repo ----

  @impl Comn.Repo
  def describe(%Handle{backend: b, state: s, name: name}) do
    with {:ok, head} <- b.head(s),
         {:ok, tail} <- b.tail(s),
         {:ok, count} <- b.count(s) do
      {:ok, %{name: name, backend: b, head: head, tail: tail, count: count}}
    end
  end

  @impl Comn.Repo
  def get(%Handle{} = h, id: id) do
    case Enum.find(observe(h, as: :events), &(&1.id == id)) do
      nil -> Comn.Repo.not_found(id)
      e -> {:ok, e}
    end
  end

  def get(%Handle{} = h, offset: offset) do
    case read(h, offset, 1) do
      {:ok, [{^offset, event}]} -> {:ok, event}
      {:ok, _} -> {:error, ErrReg.error!("repo.stream/invalid_offset", field: inspect(offset))}
      error -> error
    end
  end

  def get(%Handle{}, _opts),
    do: {:error, ErrReg.error!("repo.stream/invalid_offset", message: "get by id: or offset:")}

  @impl Comn.Repo
  def set(%Handle{} = h, opts) do
    with {:ok, e} <- Comn.Repo.fetch_event(opts), do: append(h, e)
  end

  @impl Comn.Repo
  def delete(%Handle{}, _opts), do: {:error, ErrReg.error!("repo.stream/append_only")}

  @impl Comn.Repo
  def observe(%Handle{} = h, opts \\ []) do
    pairs =
      Stream.resource(
        fn -> :head end,
        fn
          :done ->
            {:halt, nil}

          cursor ->
            case read(h, cursor, 100) do
              {:ok, []} -> {:halt, nil}
              {:ok, batch} -> {batch, elem(List.last(batch), 0) + 1}
              {:error, _} -> {:halt, nil}
            end
        end,
        fn _ -> :ok end
      )

    if Comn.Repo.events_view?(opts), do: Stream.map(pairs, &elem(&1, 1)), else: pairs
  end

  # ---- @behaviour Comn ----

  @impl Comn
  def look,
    do:
      "Stream — append-only, replayable event log with caller-tracked offsets and live subscribe"

  @impl Comn
  def recon do
    %{
      callbacks: [
        :open,
        :close,
        :drop,
        :append,
        :append_many,
        :read,
        :head,
        :tail,
        :subscribe,
        :unsubscribe
      ],
      backends: Map.keys(@backends),
      extends: Comn.Repo,
      type: :facade
    }
  end

  @impl Comn
  def choices,
    do: %{backends: ["mem", "sqlite", "jetstream"], cursors: ["head", "tail", "offset"]}

  @impl Comn
  def act(%{action: :open, name: n, opts: o}), do: open(n, o)
  def act(%{action: :open, name: n}), do: open(n, [])
  def act(input), do: Comn.unknown_action(input)

  # ---- internals ----

  defp resolve_backend(key) when is_map_key(@backends, key), do: {:ok, @backends[key]}

  defp resolve_backend(mod) when is_atom(mod) do
    if Code.ensure_loaded?(mod) and function_exported?(mod, :append, 2),
      do: {:ok, mod},
      else:
        {:error,
         ErrReg.error!("repo.stream/invalid_opts",
           field: "backend",
           suggestion: ":mem | :sqlite | :jetstream"
         )}
  end

  defp resolve_backend(_),
    do: {:error, ErrReg.error!("repo.stream/invalid_opts", field: "backend")}
end
