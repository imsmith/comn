defmodule Comn.Repo.Merkel do
  @moduledoc """
  Address a fact by its content, keep it forever, never change it, and
  prove it is unchanged.

  Public, backend-agnostic facade. Four verbs: `put/2` returns a content
  address, `get/2` returns what is behind one, `head/1` is the current root,
  `verify/1` walks root to genesis recomputing every hash. Every put
  extends a hash chain, so the root commits to everything before it; it is
  the thing you publish or sign.

  Content is anything `Comn.Event` can convert, stored as the canonical
  bytes from the `Comn.Merkel` protocol. Addresses are opaque per backend.

  Backends: `:mem` (ETS, sha256) and `:git` (a bare repository; each put is
  a commit, the address is the commit id).

  ## Examples

      iex> name = String.to_atom("merkel_doc_#{:erlang.unique_integer([:positive])}")
      iex> {:ok, m} = Comn.Repo.Merkel.open(name, backend: :mem)
      iex> event = Comn.Events.EventStruct.new(:test, "doc.fact", %{n: 1})
      iex> {:ok, address} = Comn.Repo.Merkel.put(m, event)
      iex> {:ok, ^event} = Comn.Repo.Merkel.get(m, address)
      iex> {:ok, ^address} = Comn.Repo.Merkel.head(m)
      iex> :ok = Comn.Repo.Merkel.verify(m)
      iex> Comn.Repo.Merkel.drop(m)
      :ok
  """

  @behaviour Comn
  @behaviour Comn.Repo

  alias Comn.Errors.Registry, as: ErrReg
  alias Comn.Events.EventStruct
  alias Comn.Repo.{Handle, Lifecycle}
  alias Comn.Repo.Merkel.Node

  @typedoc "Opaque merkel handle. Treat as a black box."
  @type t :: Handle.t()

  @typedoc "A content address, opaque per backend."
  @type address :: String.t()

  @backends %{mem: Comn.Repo.Merkel.Mem, git: Comn.Repo.Merkel.Git}

  @impl Comn.Repo
  def backends, do: @backends

  # ---- lifecycle ----

  @doc """
  Opens a merkel. Options: `:backend` — `:mem` (default) or `:git`;
  `:path` — required for `:git`, the bare repository directory (created
  if missing). The rest go to the backend.

  Errors: `repo.merkel/invalid_opts`, `repo.merkel/already_exists`.
  """
  @spec open(atom(), keyword()) :: {:ok, t()} | {:error, Comn.Errors.ErrorStruct.t()}
  def open(name, opts \\ []) when is_atom(name) and is_list(opts),
    do: Lifecycle.open(__MODULE__, name, Keyword.put_new(opts, :backend, :mem))

  @doc "Releases the handle. A durable backend keeps its chain. Idempotent."
  @spec close(t()) :: :ok
  def close(%Handle{} = h), do: Lifecycle.close(h)

  @doc "Deletes the merkel and its whole chain. Idempotent."
  @spec drop(t()) :: :ok
  def drop(%Handle{} = h), do: Lifecycle.drop(h)

  # ---- merkel verbs ----

  @doc """
  Stores a fact as a new node linked to the current root and returns its
  address. The fact is anything `Comn.Event` converts.

  Errors: `repo.merkel/invalid_event`.
  """
  @spec put(t(), term()) :: {:ok, address()} | {:error, Comn.Errors.ErrorStruct.t()}
  def put(%Handle{backend: b, state: s}, term) do
    case Comn.Event.to_event(term) do
      {:ok, %EventStruct{} = e} -> b.put(s, Comn.Merkel.to_content(e))
      {:error, _} -> {:error, ErrReg.error!("repo.merkel/invalid_event", field: inspect(term))}
    end
  end

  @doc "The whole node behind an address, hashes and parent link included."
  @spec node(t(), address()) :: {:ok, Node.t()} | {:error, Comn.Errors.ErrorStruct.t()}
  def node(%Handle{backend: b, state: s}, address) when is_binary(address), do: b.node(s, address)

  @doc "The root address, or nil when empty."
  @spec head(t()) :: {:ok, address() | nil} | {:error, Comn.Errors.ErrorStruct.t()}
  def head(%Handle{backend: b, state: s}), do: b.head(s)

  @doc """
  Walks from the root to genesis recomputing every node's hashes.
  Returns `:ok`, or `repo.merkel/tampered` naming the first address whose
  stored content no longer matches.
  """
  @spec verify(t()) :: :ok | {:error, Comn.Errors.ErrorStruct.t()}
  def verify(%Handle{backend: b, state: s} = m) do
    with {:ok, root} <- head(m), do: walk_verify(b, s, root)
  end

  defp walk_verify(_b, _s, nil), do: :ok

  defp walk_verify(b, s, address) do
    case b.node(s, address) do
      {:ok, %Node{parent: parent} = node} ->
        if b.check(s, node) == :ok,
          do: walk_verify(b, s, parent),
          else: {:error, ErrReg.error!("repo.merkel/tampered", field: address)}

      {:error, _} ->
        {:error, ErrReg.error!("repo.merkel/tampered", field: address)}
    end
  end

  # ---- @behaviour Comn.Repo ----

  @impl Comn.Repo
  def describe(%Handle{backend: b, state: s, name: name} = m) do
    with {:ok, root} <- head(m),
         {:ok, len} <- b.length(s) do
      {:ok, %{name: name, backend: b, root: root, length: len}}
    end
  end

  @doc """
  The fact behind an address (`get(m, address)` or `get(m, address: a)`),
  or by event id (`get(m, id: i)`, a scan from the root).

  Errors: `repo.merkel/unknown_address`, `repo/event_not_found`.
  """
  @spec get(t(), address() | keyword()) :: {:ok, term()} | {:error, Comn.Errors.ErrorStruct.t()}
  @impl Comn.Repo
  def get(%Handle{} = m, address) when is_binary(address) do
    with {:ok, %Node{content: content}} <- node(m, address), do: {:ok, from_content(content)}
  end

  def get(%Handle{} = m, address: address), do: get(m, address)

  def get(%Handle{} = m, id: id) do
    case Enum.find(observe(m, as: :events), &(&1.id == id)) do
      nil -> Comn.Repo.not_found(id)
      e -> {:ok, e}
    end
  end

  def get(%Handle{}, _opts),
    do: {:error, ErrReg.error!("repo.merkel/unknown_address", message: "get by address: or id:")}

  @impl Comn.Repo
  def set(%Handle{} = m, opts) do
    with {:ok, e} <- Comn.Repo.fetch_event(opts), do: put(m, e)
  end

  @impl Comn.Repo
  def delete(%Handle{}, _opts), do: {:error, ErrReg.error!("repo.merkel/immutable")}

  @doc "Lazily walks the chain from root to genesis: nodes, or with `as: :events` the facts."
  @impl Comn.Repo
  def observe(%Handle{backend: b, state: s} = m, opts \\ []) do
    nodes =
      Stream.resource(
        fn ->
          case head(m) do
            {:ok, root} -> root
            _ -> nil
          end
        end,
        fn
          nil ->
            {:halt, nil}

          address ->
            case b.node(s, address) do
              {:ok, %Node{parent: parent} = node} -> {[node], parent}
              _ -> {:halt, nil}
            end
        end,
        fn _ -> :ok end
      )

    if Comn.Repo.events_view?(opts),
      do:
        nodes
        |> Stream.map(&from_content(&1.content))
        |> Stream.filter(&is_struct(&1, EventStruct)),
      else: nodes
  end

  # ---- @behaviour Comn ----

  @impl Comn
  def look, do: "Merkel — content-addressed, immutable, verifiable hash chain of facts"

  @impl Comn
  def recon do
    %{
      callbacks: [:open, :close, :drop, :put, :get, :node, :head, :verify],
      backends: Map.keys(@backends),
      extends: Comn.Repo,
      type: :facade
    }
  end

  @impl Comn
  def choices, do: %{backends: ["mem", "git"]}

  @impl Comn
  def act(%{action: :open, name: n, opts: o}), do: open(n, o)
  def act(%{action: :open, name: n}), do: open(n, [])
  def act(input), do: Comn.unknown_action(input)

  # ---- internals ----

  # ponytail: content is ETF when it came from a term and raw otherwise; a raw
  # binary that happens to be valid ETF would decode. Tag the encoding if that bites.
  defp from_content(content) do
    Comn.Repo.decode_term(content)
  rescue
    ArgumentError -> content
  end
end
