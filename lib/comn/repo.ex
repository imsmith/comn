defmodule Comn.Repo do
  @moduledoc """
  Common I/O behaviour for data repositories.

  Defines the five verbs every repo must support — `describe`, `get`, `set`,
  `delete`, `observe` — regardless of whether the backend is a table, file,
  graph, or shell command. Extension behaviours (`Comn.Repo.Table`,
  `Comn.Repo.File`, `Comn.Repo.Graphs`, `Comn.Repo.Cmd`) add domain-specific
  callbacks on top of these.

  Also implements `@behaviour Comn` for uniform introspection.

  ## Spatial callbacks (optional)

  Repos that have a notion of *place* implement three optional callbacks:
  `enter/2`, `exit/2`, and `discover/2`, all keyed by a `Comn.Zone`.
  `Comn.Repo.Graphs.Graph` implements them — vertices are zone locales,
  `discover/2` returns adjacent vertices, and `traverse/4` (a graph-only
  extension) walks the graph and updates the calling process's context
  zone.

  Flat repos like `Comn.Repo.Table.ETS` do **not** implement these. Use
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

  Errors: `repo/event_not_found`, `repo.file/invalid_state`, `repo.graph/missing_key`.
  """
  @callback get(resource(), keyword()) :: {:ok, term()} | {:error, term()}

  @doc """
  Stores a value. Opts must include `:key` and `:value` (or backend equivalent).

  Canonical form (ADR-0001): `set(resource, event: %Comn.Events.EventStruct{})`.
  Every shape accepts it and does what its medium does with a fact: a table
  stores it under the id, a file appends a line, a queue enqueues, a stream
  appends. Anything else under `:event` is `repo/invalid_event`.

  Errors: `repo/invalid_event`, `repo.table/not_found`, `repo.file/invalid_state`, `repo.graph/missing_key`.
  """
  @callback set(resource(), keyword()) :: :ok | {:ok, term()} | {:error, term()}

  @doc """
  Removes a value. Opts must include `:key` (or backend equivalent).

  Errors: `repo.table/not_found`, `repo.graph/missing_key`.
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

  @optional_callbacks enter: 2, exit: 2, discover: 2

  # Helpers for the canonical event forms, shared by every shape.

  @doc "True when `opts` carry the canonical `event:` form."
  @spec event?(keyword()) :: boolean()
  def event?(opts) when is_list(opts), do: Keyword.has_key?(opts, :event)

  @doc "True when `opts` ask for the canonical `as: :events` view."
  @spec events_view?(keyword()) :: boolean()
  def events_view?(opts) when is_list(opts), do: Keyword.get(opts, :as) == :events

  @doc "Fetches and validates the `event:` option."
  @spec fetch_event(keyword()) :: {:ok, Comn.Events.EventStruct.t()} | {:error, Comn.Errors.ErrorStruct.t()}
  def fetch_event(opts) when is_list(opts) do
    case Keyword.fetch(opts, :event) do
      {:ok, %Comn.Events.EventStruct{} = e} -> {:ok, e}
      {:ok, other} -> {:error, Comn.Errors.Registry.error!("repo/invalid_event", field: inspect(other))}
      :error -> {:error, Comn.Errors.Registry.error!("repo/invalid_event", message: "missing :event option")}
    end
  end

  @doc "The `repo/event_not_found` error for an event id."
  @spec not_found(term()) :: {:error, Comn.Errors.ErrorStruct.t()}
  def not_found(id), do: {:error, Comn.Errors.Registry.error!("repo/event_not_found", field: inspect(id))}

  @doc "Encodes an event as one log line (base64 of the external term format)."
  @spec encode_line(Comn.Events.EventStruct.t()) :: binary()
  def encode_line(%Comn.Events.EventStruct{} = e), do: Base.encode64(:erlang.term_to_binary(e)) <> "\n"

  @doc "Decodes a line written by `encode_line/1`; nil for anything else."
  @spec decode_line(binary()) :: Comn.Events.EventStruct.t() | nil
  def decode_line(line) when is_binary(line) do
    with {:ok, bin} <- Base.decode64(String.trim_trailing(line)),
         %Comn.Events.EventStruct{} = e <- :erlang.binary_to_term(bin, [:safe]) do
      e
    else
      _ -> nil
    end
  rescue
    ArgumentError -> nil
  end

  @impl Comn
  def look, do: "Repo — common I/O behaviour for data repositories (tables, files, graphs, commands)"

  @impl Comn
  def recon do
    %{
      callbacks: [:describe, :get, :set, :delete, :observe],
      extensions: [Comn.Repo.Table, Comn.Repo.File, Comn.Repo.Graphs, Comn.Repo.Cmd],
      type: :behaviour
    }
  end

  @impl Comn
  def choices do
    %{
      extensions: ["Table", "File", "Graphs", "Cmd"],
      implementations: ["Table.ETS", "File.Local", "File.NFS", "File.IPFS", "Graphs.Graph", "Cmd.Shell"]
    }
  end

  @impl Comn
  def act(_input), do: Comn.behaviour_only()
end
