defmodule Comn.Repo.Bus do
  @moduledoc """
  Publish a fact to every current subscriber; retain nothing.

  Public, backend-agnostic facade (ADR-0001). The bus is the Repo shape
  whose medium delivers to everyone listening right now and keeps nothing
  for anyone who was not. `set/2` publishes, `observe/2` is a live stream,
  `get/2` and `delete/2` are `repo.bus/not_retained`.

  Subscribers receive `{:bus, name, event}`. Events are
  `Comn.Events.EventStruct`; `subscribe/2` can filter on `event.topic`.

  Backends: `:registry` (local, default). A NATS core backend is the
  natural second one.

  ## Examples

      iex> name = String.to_atom("bus_doc_#{:erlang.unique_integer([:positive])}")
      iex> {:ok, b} = Comn.Repo.Bus.open(name)
      iex> {:ok, ref} = Comn.Repo.Bus.subscribe(b)
      iex> event = Comn.Events.EventStruct.new(:test, "doc.ping", %{})
      iex> :ok = Comn.Repo.Bus.publish(b, event)
      iex> receive do
      ...>   {:bus, ^name, ^event} -> :delivered
      ...> end
      :delivered
      iex> Comn.Repo.Bus.unsubscribe(b, ref)
      :ok
  """

  @behaviour Comn
  @behaviour Comn.Repo

  alias Comn.Errors.Registry, as: ErrReg
  alias Comn.Events.EventStruct
  alias Comn.Repo.{Handle, Lifecycle}

  @typedoc "Opaque bus handle. Treat as a black box."
  @type t :: Handle.t()

  @backends %{registry: Comn.Repo.Bus.Registry}

  @impl Comn.Repo
  def backends, do: @backends

  # Subscribers live in the shared Comn.EventBus registry under {:bus, name};
  # the registry value is the subscription's {ref, topic_filter}.
  @registry Comn.EventBus

  # ---- lifecycle ----

  @doc """
  Opens a bus. Options: `:backend` — `:registry` (default) or a module
  implementing the private backend contract; the rest go to the backend.

  Errors: `repo.bus/invalid_opts`, `repo.bus/already_exists`.
  """
  @spec open(atom(), keyword()) :: {:ok, t()} | {:error, Comn.Errors.ErrorStruct.t()}
  def open(name, opts \\ []) when is_atom(name) and is_list(opts),
    do: Lifecycle.open(__MODULE__, name, Keyword.put_new(opts, :backend, :registry))

  @doc "Releases the handle. Idempotent."
  @spec close(t()) :: :ok
  def close(%Handle{} = h), do: Lifecycle.close(h)

  @doc "Closes the bus and releases any backend resources. Idempotent."
  @spec drop(t()) :: :ok
  def drop(%Handle{} = h), do: Lifecycle.drop(h)

  # ---- bus verbs ----

  @doc "Publishes an event to every current subscriber. Errors: `repo.bus/invalid_event`."
  @spec publish(t(), EventStruct.t()) :: :ok | {:error, Comn.Errors.ErrorStruct.t()}
  def publish(%Handle{backend: b, state: s}, %EventStruct{} = event), do: b.publish(s, event)

  def publish(%Handle{}, other),
    do: {:error, ErrReg.error!("repo.bus/invalid_event", field: inspect(other))}

  @doc """
  Subscribes the calling process; it receives `{:bus, name, event}` for
  every event published afterwards. `topic: t` delivers only events whose
  topic equals `t`. Returns a reference for `unsubscribe/2`; the
  subscription ends when the subscriber exits.
  """
  @spec subscribe(t(), keyword()) :: {:ok, reference()} | {:error, Comn.Errors.ErrorStruct.t()}
  def subscribe(%Handle{backend: b, state: s, name: name}, opts \\ []) do
    ref = make_ref()

    with {:ok, _owner} <-
           Registry.register(@registry, {:bus, name}, {ref, Keyword.get(opts, :topic)}),
         :ok <- b.subscribe(s) do
      {:ok, ref}
    end
  end

  @doc "Cancels a subscription made by `subscribe/2`."
  @spec unsubscribe(t(), reference()) :: :ok
  def unsubscribe(%Handle{name: name}, ref) when is_reference(ref) do
    Registry.unregister_match(@registry, {:bus, name}, {ref, :_})
  end

  @doc false
  # Called by backends for every event that should reach local subscribers.
  def notify(name, %EventStruct{topic: topic} = event) do
    Registry.dispatch(@registry, {:bus, name}, fn entries ->
      for {pid, {_ref, filter}} <- entries,
          filter in [nil, topic],
          do: send(pid, {:bus, name, event})
    end)
  end

  # ---- @behaviour Comn.Repo ----

  @impl Comn.Repo
  def describe(%Handle{backend: b, name: name}) do
    {:ok,
     %{name: name, backend: b, subscribers: length(Registry.lookup(@registry, {:bus, name}))}}
  end

  @impl Comn.Repo
  def get(%Handle{}, _opts), do: {:error, ErrReg.error!("repo.bus/not_retained")}

  @impl Comn.Repo
  def set(%Handle{} = h, opts) do
    case Comn.Repo.fetch_event(opts) do
      {:ok, e} ->
        publish(h, e)

      {:error, _} ->
        {:error,
         ErrReg.error!("repo.bus/invalid_event", field: inspect(Keyword.get(opts, :event)))}
    end
  end

  @impl Comn.Repo
  def delete(%Handle{}, _opts), do: {:error, ErrReg.error!("repo.bus/not_retained")}

  @doc """
  A live stream of events: subscribes when enumeration starts and yields
  each delivered event. Never ends on its own; take what you need.
  """
  @impl Comn.Repo
  def observe(%Handle{name: name} = h, opts \\ []) do
    topic = Keyword.get(opts, :topic)

    Stream.resource(
      fn ->
        {:ok, ref} = subscribe(h, topic: topic)
        ref
      end,
      fn ref ->
        receive do
          {:bus, ^name, event} -> {[event], ref}
        end
      end,
      fn ref -> unsubscribe(h, ref) end
    )
  end

  # ---- @behaviour Comn ----

  @impl Comn
  def look, do: "Bus — publish a fact to every current subscriber; retain nothing"

  @impl Comn
  def recon do
    %{
      callbacks: [:open, :close, :drop, :publish, :subscribe, :unsubscribe],
      backends: Map.keys(@backends),
      extends: Comn.Repo,
      type: :facade
    }
  end

  @impl Comn
  def choices, do: %{backends: ["registry"]}

  @impl Comn
  def act(%{action: :open, name: n, opts: o}), do: open(n, o)
  def act(%{action: :open, name: n}), do: open(n, [])
  def act(input), do: Comn.unknown_action(input)
end
