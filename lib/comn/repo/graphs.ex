defmodule Comn.Repo.Graphs do
  @moduledoc """
  Graphs: the data is the connections.

  Public, backend-agnostic facade. Callers go through this module; the
  backend is a word in one option to `open/2`. Backends: `:libgraph`
  (in-memory value; see `Comn.Repo.Graphs.Graph`).

  A graph is a value, so the verbs that change it (`link/4`, `unlink/4`,
  and the `Comn.Repo` `set/2` and `delete/2`) return a new handle. Node
  CRUD is the base `Comn.Repo` verbs; `traverse/2` runs queries; the
  spatial verbs `enter/2`, `exit/2`, `discover/2`, and `traverse/4` treat
  vertices as `Comn.Zone` locales.

  This module also remains the behaviour older backends implement directly;
  `Comn.Repo.Graphs.Graph` keeps its public surface.

  ## Examples

      iex> {:ok, g} = Comn.Repo.Graphs.open("deps")
      iex> {:ok, g} = Comn.Repo.Graphs.link(g, :phoenix, :plug)
      iex> {:ok, g} = Comn.Repo.Graphs.link(g, :plug, :cowboy)
      iex> Comn.Repo.Graphs.traverse(g, type: :shortest_path, from: :phoenix, to: :cowboy)
      {:ok, [:phoenix, :plug, :cowboy]}
  """

  @behaviour Comn
  @behaviour Comn.Repo

  alias Comn.Repo.Graphs.GraphStruct
  alias Comn.Repo.{Handle, Lifecycle}
  alias Comn.Zone

  @typedoc "Opaque graph handle. Treat as a black box."
  @type t :: Handle.t()

  @backends %{libgraph: Comn.Repo.Graphs.GraphAdapter}

  @impl Comn.Repo
  def backends, do: @backends

  # ---- behaviour for direct backends (kept for Comn.Repo.Graphs.Graph) ----

  @doc """
  Creates a directed edge from `from` to `to`. Adds vertices if they don't exist.

  Opts: `:label`, `:weight`.
  """
  @callback link(graph :: GraphStruct.t(), from :: term(), to :: term(), opts :: keyword()) ::
              {:ok, GraphStruct.t()} | {:error, term()}

  @doc "Removes the edge from `from` to `to`."
  @callback unlink(graph :: GraphStruct.t(), from :: term(), to :: term(), opts :: keyword()) ::
              {:ok, GraphStruct.t()} | {:error, term()}

  @doc """
  Runs a query against the graph. Requires `type:` in the query keyword list.

  Query types: `:shortest_path` (requires `:from`, `:to`), `:reachable` (requires `:from`),
  `:neighbors` (requires `:vertex`), `:vertices`, `:edges`.

  Errors: `{:unknown_query_type, type}` (`repo.graphs/unknown_query_type`).
  """
  @callback traverse(graph :: GraphStruct.t(), query :: keyword()) ::
              {:ok, term()} | {:error, term()}

  # ---- lifecycle ----

  @doc """
  Opens a graph. `name` is any term and is carried on the graph.

  Options: `:backend` — `:libgraph` (default) or a module implementing the
  private backend contract; `:directed?` (default `true`), `:id`,
  `:metadata`. The rest go to the backend.

  Errors: `repo.graphs/invalid_opts`.
  """
  @spec open(term(), keyword()) :: {:ok, t()} | {:error, Comn.Errors.ErrorStruct.t()}
  def open(name, opts \\ []) when is_list(opts),
    do: Lifecycle.open(__MODULE__, name, Keyword.put_new(opts, :backend, :libgraph))

  @doc "Releases the handle. A value backend has nothing to release. Idempotent."
  @spec close(t()) :: :ok
  def close(%Handle{} = h), do: Lifecycle.close(h)

  @doc "Deletes the graph. Idempotent."
  @spec drop(t()) :: :ok
  def drop(%Handle{} = h), do: Lifecycle.drop(h)

  # ---- graph verbs ----

  @doc "Adds a directed edge (and any missing vertices). Opts: `:label`, `:weight`. Returns the new handle."
  @spec link(t(), term(), term(), keyword()) :: {:ok, t()} | {:error, Comn.Errors.ErrorStruct.t()}
  def link(%Handle{backend: b, state: s} = h, from, to, opts \\ []),
    do: Lifecycle.rebind(h, b.link(s, from, to, opts))

  @doc "Removes the edge from `from` to `to`. Returns the new handle."
  @spec unlink(t(), term(), term(), keyword()) ::
          {:ok, t()} | {:error, Comn.Errors.ErrorStruct.t()}
  def unlink(%Handle{backend: b, state: s} = h, from, to, opts \\ []),
    do: Lifecycle.rebind(h, b.unlink(s, from, to, opts))

  @doc """
  Runs a query. `type:` is `:shortest_path` (`from:`, `to:`), `:reachable`
  (`from:`), `:neighbors` (`vertex:`), `:vertices`, or `:edges`.

  Errors: `repo.graphs/unknown_query_type`, `repo.graphs/unreachable`.
  """
  @spec traverse(t(), keyword()) :: {:ok, term()} | {:error, Comn.Errors.ErrorStruct.t()}
  def traverse(%Handle{backend: b, state: s}, query) when is_list(query), do: b.traverse(s, query)

  @doc "Spatial traversal from a zone to a vertex; updates the calling process's context zone."
  @spec traverse(t(), Zone.t(), term(), keyword()) ::
          {:ok, term()} | {:error, Comn.Errors.ErrorStruct.t()}
  def traverse(%Handle{backend: b, state: s}, %Zone{} = from, to, opts),
    do: b.traverse(s, from, to, opts)

  # ---- @behaviour Comn.Repo ----

  @impl Comn.Repo
  def describe(%Handle{backend: b, state: s}), do: b.describe(s)

  @doc "`get(g, vertex: v)` confirms a vertex; `get(g, id: event_id)` returns a stored event."
  @impl Comn.Repo
  def get(%Handle{backend: b, state: s}, opts), do: b.get(s, opts)

  @doc "`set(g, vertex: v)` adds a vertex; `set(g, event: e)` stores the event as a vertex. Returns the new handle."
  @impl Comn.Repo
  def set(%Handle{backend: b, state: s} = h, opts), do: Lifecycle.rebind(h, b.set(s, opts))

  @doc "`delete(g, vertex: v)` removes a vertex and its edges. Returns the new handle."
  @impl Comn.Repo
  def delete(%Handle{backend: b, state: s} = h, opts), do: Lifecycle.rebind(h, b.delete(s, opts))

  @impl Comn.Repo
  def observe(%Handle{backend: b, state: s}, opts \\ []), do: b.observe(s, opts)

  @impl Comn.Repo
  def enter(%Handle{backend: b, state: s}, %Zone{} = zone), do: b.enter(s, zone)

  @impl Comn.Repo
  def exit(%Handle{backend: b, state: s}, %Zone{} = zone), do: b.exit(s, zone)

  @impl Comn.Repo
  def discover(%Handle{backend: b, state: s}, %Zone{} = zone), do: b.discover(s, zone)

  # ---- @behaviour Comn ----

  @impl Comn
  def look, do: "Graphs — link, unlink, and traverse nodes and edges"

  @impl Comn
  def recon do
    %{
      callbacks: [:open, :close, :drop, :link, :unlink, :traverse],
      backends: Map.keys(@backends),
      extends: Comn.Repo,
      traverse_types: [:shortest_path, :reachable, :neighbors, :vertices, :edges],
      type: :facade
    }
  end

  @impl Comn
  def choices do
    %{
      backends: ["libgraph"],
      traversal: ["shortest_path", "reachable", "neighbors", "vertices", "edges"]
    }
  end

  @impl Comn
  def act(%{action: :open, name: n, opts: o}), do: open(n, o)
  def act(%{action: :open, name: n}), do: open(n, [])
  def act(input), do: Comn.unknown_action(input)
end
