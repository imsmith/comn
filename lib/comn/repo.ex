defmodule Comn.Repo do
  @moduledoc """
  Common I/O behaviour for data repositories.

  Defines the five verbs every repo must support — `describe`, `get`, `set`,
  `delete`, `observe` — regardless of whether the backend is a table, file,
  graph, or shell command. Each shape (`Comn.Repo.Table`, `Column`, `File`,
  `Graphs`, `Batch`, `Queue`, `Bus`, `Stream`, `Merkel`) is a facade over
  fungible backends and adds its own verbs on top of these; `Comn.Repo.Cmd`
  is the execution shape.

  ## Handles and lifecycle

  Every shape's `open/2` returns a `Comn.Repo.Handle` and every shape's
  `close/1` and `drop/1` go through `Comn.Repo.Lifecycle`. The backend is a
  word in one option to `open/2`; a facade exposes `backends/0` and the
  lifecycle resolves it, checking that the module declares the shape's
  `Backend` behaviour. Calling code never names a backend after that.

  ## Canonical event forms (ADR-0001)

  Every shape accepts `set(h, event: e)`, answers `get(h, id: event_id)`
  where it retains anything, and enumerates `observe(h, as: :events)`. The
  helpers below (`event?/1`, `events_view?/1`, `fetch_event/1`,
  `events_in/1`, `encode_line/1`, `decode_line/1`, `decode_term/1`) are
  what the shapes share to implement them.

  Also implements `@behaviour Comn` for uniform introspection.

  ## Spatial callbacks (optional)

  Repos that have a notion of *place* implement three optional callbacks:
  `enter/2`, `exit/2`, and `discover/2`, all keyed by a `Comn.Zone`.
  `Comn.Repo.Graphs.Graph` implements them — vertices are zone locales,
  `discover/2` returns adjacent vertices, and `traverse/4` (a graph-only
  extension) walks the graph and updates the calling process's context
  zone.

  Flat repos like `Comn.Repo.Table` do **not** implement these. Use
  `function_exported?/3` or `behaviour_info(:optional_callbacks)` to
  detect spatial-capability at runtime.

  ## Examples

      iex> Comn.Repo.look()
      "Repo — common I/O behaviour for data repositories (tables, files, graphs, commands)"

      iex> %{extensions: exts} = Comn.Repo.recon()
      iex> Comn.Repo.Table in exts
      true
  """

  @behaviour Comn

  @typedoc "The resource being operated on — a table name, file handle, graph struct, etc."
  @type resource :: term()

  @doc """
  Returns metadata about the resource (table info, file stat, graph summary).

  Errors: `repo.table/not_found`, `repo.file/invalid_state`.
  """
  @callback describe(resource()) :: {:ok, map()} | {:error, term()}

  @doc """
  Retrieves a value. Opts specify the key or query.

  Canonical form (ADR-0001): `get(resource, id: event_id)` returns the
  stored `Comn.Events.EventStruct` with that id, or `repo/event_not_found`.

  Errors: `repo/event_not_found`, `repo.file/invalid_state`, `repo.graphs/missing_key`.
  """
  @callback get(resource(), keyword()) :: {:ok, term()} | {:error, term()}

  @doc """
  Stores a value. Opts must include `:key` and `:value` (or backend equivalent).

  Canonical form (ADR-0001): `set(resource, event: %Comn.Events.EventStruct{})`.
  Every shape accepts it and does what its medium does with a fact: a table
  stores it under the id, a file appends a line, a queue enqueues, a stream
  appends. Anything else under `:event` is `repo/invalid_event`.

  Errors: `repo/invalid_event`, `repo.table/not_found`, `repo.file/invalid_state`, `repo.graphs/missing_key`.
  """
  @callback set(resource(), keyword()) :: :ok | {:ok, term()} | {:error, term()}

  @doc """
  Removes a value. Opts must include `:key` (or backend equivalent).

  Errors: `repo.table/not_found`, `repo.graphs/missing_key`.
  """
  @callback delete(resource(), keyword()) :: :ok | {:ok, term()} | {:error, term()}

  @doc """
  Returns a stream or snapshot of the resource's contents.

  Canonical form (ADR-0001): `observe(resource, as: :events)` enumerates the
  stored `Comn.Events.EventStruct` values and nothing else.

  Errors: `repo.table/not_found`, `repo.file/invalid_state`.
  """
  @callback observe(resource(), keyword()) :: Enumerable.t() | {:error, term()}

  @doc """
  Spatial: position into a zone within this repo.

  Optional. Spatial repos (graphs, presence-aware stores) implement; flat
  repos (ETS tables, blob stores) do not. Returns `{:ok, position}` where
  position is repo-defined context, or `{:error, _}` if the zone is not
  reachable in this repo.
  """
  @callback enter(resource(), Comn.Zone.t()) :: {:ok, term()} | {:error, term()}

  @doc "Spatial: clear positional state for a zone. Optional."
  @callback exit(resource(), Comn.Zone.t()) :: :ok | {:error, term()}

  @doc """
  Spatial: list zones reachable from the given zone.

  Optional. Returns `{:ok, [zone_or_locator]}` for spatial repos.
  """
  @callback discover(resource(), Comn.Zone.t()) :: {:ok, list()} | {:error, term()}

  # ---- lifecycle (handle-based shapes; see Comn.Repo.Lifecycle) ----

  @doc "Short backend names to backend modules, e.g. `%{ets: Comn.Repo.Table.ETSAdapter}`."
  @callback backends() :: %{atom() => module()}

  # Column, File, Graphs, and Batch predate the handle lifecycle and expose their
  # own structs and open/close verbs; `backends/0` stays optional until they converge.
  @optional_callbacks enter: 2, exit: 2, discover: 2, backends: 0

  # Helpers for the canonical event forms, shared by every shape.

  @doc "True when `opts` carry the canonical `event:` form."
  @spec event?(keyword()) :: boolean()
  def event?(opts) when is_list(opts), do: Keyword.has_key?(opts, :event)

  @doc "True when `opts` ask for the canonical `as: :events` view."
  @spec events_view?(keyword()) :: boolean()
  def events_view?(opts) when is_list(opts), do: Keyword.get(opts, :as) == :events

  @doc "The events among keyed `{key, value}` pairs, for the `as: :events` view."
  @spec events_in([{term(), term()}]) :: [Comn.Events.EventStruct.t()]
  def events_in(pairs), do: for({_k, %Comn.Events.EventStruct{} = e} <- pairs, do: e)

  @doc """
  Fetches the `event:` option and converts it through the `Comn.Event`
  protocol, so a map or tuple is an event by default. Anything the
  protocol rejects is `repo/invalid_event`.
  """
  @spec fetch_event(keyword()) ::
          {:ok, Comn.Events.EventStruct.t()} | {:error, Comn.Errors.ErrorStruct.t()}
  def fetch_event(opts) when is_list(opts) do
    with {:ok, term} <- Keyword.fetch(opts, :event),
         {:ok, %Comn.Events.EventStruct{} = e} <- Comn.Event.to_event(term) do
      {:ok, e}
    else
      :error ->
        {:error,
         Comn.Errors.Registry.error!("repo/invalid_event", message: "missing :event option")}

      {:error, _} ->
        {:error,
         Comn.Errors.Registry.error!("repo/invalid_event",
           field: inspect(Keyword.get(opts, :event))
         )}
    end
  end

  @doc "The `repo/event_not_found` error for an event id."
  @spec not_found(term()) :: {:error, Comn.Errors.ErrorStruct.t()}
  def not_found(id),
    do: {:error, Comn.Errors.Registry.error!("repo/event_not_found", field: inspect(id))}

  @doc "Encodes an event as one log line (base64 of the external term format)."
  @spec encode_line(Comn.Events.EventStruct.t()) :: binary()
  def encode_line(%Comn.Events.EventStruct{} = e),
    do: Base.encode64(:erlang.term_to_binary(e)) <> "\n"

  @spec decode_term(binary()) :: term()
  @doc """
  Decodes a term a Comn backend wrote with `:erlang.term_to_binary/1`.

  Non-executable and `:safe`: no new atoms, and no funs, pids, ports, or
  references anywhere in the term (`ArgumentError` if present). The bytes
  come from a medium the backend itself writes (a SQLite file, a JetStream
  subject, an Ecto column, a log line); a hostile peer on the same medium
  can still make a large term, which is a size limit for the medium, not
  for this function. Every backend decodes through here.

      iex> Comn.Repo.decode_term(:erlang.term_to_binary(%{"n" => 1}))
      %{"n" => 1}

      iex> try do
      ...>   Comn.Repo.decode_term(:erlang.term_to_binary(fn -> :boom end))
      ...> rescue
      ...>   ArgumentError -> :refused
      ...> end
      :refused
  """
  def decode_term(bin) when is_binary(bin),
    do: Plug.Crypto.non_executable_binary_to_term(bin, [:safe])

  @doc "Decodes a line written by `encode_line/1`; nil for anything else."
  @spec decode_line(binary()) :: Comn.Events.EventStruct.t() | nil
  def decode_line(line) when is_binary(line) do
    with {:ok, bin} <- Base.decode64(String.trim_trailing(line)),
         %Comn.Events.EventStruct{} = e <- decode_term(bin) do
      e
    else
      _ -> nil
    end
  rescue
    ArgumentError -> nil
  end

  @impl Comn
  def look,
    do: "Repo — common I/O behaviour for data repositories (tables, files, graphs, commands)"

  @impl Comn
  def recon do
    %{
      callbacks: [:describe, :get, :set, :delete, :observe],
      extensions: [
        Comn.Repo.Table,
        Comn.Repo.Column,
        Comn.Repo.File,
        Comn.Repo.Graphs,
        Comn.Repo.Batch,
        Comn.Repo.Queue,
        Comn.Repo.Bus,
        Comn.Repo.Stream,
        Comn.Repo.Merkel,
        Comn.Repo.Cmd
      ],
      type: :behaviour
    }
  end

  @impl Comn
  def choices do
    %{
      extensions: [
        "Table",
        "Column",
        "File",
        "Graphs",
        "Batch",
        "Queue",
        "Bus",
        "Stream",
        "Merkel",
        "Cmd"
      ],
      implementations: [
        "Table.ETS",
        "Table.Ecto",
        "Column.ETS",
        "File.Local",
        "File.NFS",
        "File.IPFS",
        "Graphs.Graph",
        "Batch.Mem",
        "Queue.Mem",
        "Queue.SQLite",
        "Bus.Registry",
        "Stream.Mem",
        "Stream.SQLite",
        "Stream.JetStream",
        "Merkel.Mem",
        "Merkel.Git",
        "Cmd.Shell"
      ]
    }
  end

  @impl Comn
  def act(_input), do: Comn.behaviour_only()
end
