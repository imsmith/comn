defmodule Comn.Repo.Table do
  @moduledoc """
  Key-value tables.

  Public, backend-agnostic facade. Callers go through this module; the
  backend is a word in one option to `open/2` and the calling code never
  changes. Backends: `:ets` (in-memory, dies with its owner) and `:ecto`
  (any Ecto adapter; see `Comn.Repo.Table.Ecto`).

  Verbs: `get/2`, `set/3`, `delete/2`, `keys/1`, `count/1`, plus the
  `Comn.Repo` forms (`set(t, event: e)` stores an event under its id,
  `get(t, id: i)`, `observe(t, as: :events)`). Per-call options such as
  `schema:` are passed to backends that understand them.

  This module also remains the behaviour older backends implement
  directly (`create`, `drop`, `keys`, `count`); `Comn.Repo.Table.ETS`
  keeps its public surface.

  ## Examples

      iex> name = String.to_atom("table_doc_#{:erlang.unique_integer([:positive])}")
      iex> {:ok, t} = Comn.Repo.Table.open(name, backend: :ets)
      iex> :ok = Comn.Repo.Table.set(t, "user:1", %{name: "Ian"})
      iex> {:ok, %{name: "Ian"}} = Comn.Repo.Table.get(t, "user:1")
      iex> {:ok, 1} = Comn.Repo.Table.count(t)
      iex> Comn.Repo.Table.drop(t)
      :ok
  """

  @behaviour Comn
  @behaviour Comn.Repo

  alias Comn.Errors.Registry, as: ErrReg
  alias Comn.Events.EventStruct
  alias Comn.Repo.{Handle, Lifecycle}

  @typedoc "Opaque table handle. Treat as a black box."
  @type t :: Handle.t()

  @backends %{ets: Comn.Repo.Table.ETSAdapter, ecto: Comn.Repo.Table.Ecto}

  @impl Comn.Repo
  def backends, do: @backends

  # ---- behaviour for direct backends (kept for Comn.Repo.Table.ETS) ----

  @doc "Creates a new table. Errors: `repo.table/already_exists`."
  @callback create(name :: atom(), opts :: keyword()) :: {:ok, term()} | {:error, term()}
  @doc "Destroys a table and all its data. Errors: `repo.table/not_found`."
  @callback drop(name :: atom()) :: :ok | {:error, term()}
  @doc "Returns all keys in the table. Errors: `repo.table/not_found`."
  @callback keys(name :: atom()) :: {:ok, [term()]} | {:error, term()}
  @doc "Returns the number of entries. Errors: `repo.table/not_found`."
  @callback count(name :: atom()) :: {:ok, non_neg_integer()} | {:error, term()}

  # ---- lifecycle ----

  @doc """
  Opens a table.

  Options: `:backend` — `:ets` (default) or `:ecto`, or a module implementing
  the private backend contract; the rest go to the backend.

  Errors: `repo.table/invalid_opts`, `repo.table/already_exists`.
  """
  @spec open(atom(), keyword()) :: {:ok, t()} | {:error, Comn.Errors.ErrorStruct.t()}
  def open(name, opts \\ []) when is_atom(name) and is_list(opts),
    do: Lifecycle.open(__MODULE__, name, Keyword.put_new(opts, :backend, :ets))

  @doc "Releases the handle. A durable backend keeps its data. Idempotent."
  @spec close(t()) :: :ok
  def close(%Handle{} = h), do: Lifecycle.close(h)

  @doc "Deletes the table and its data. Idempotent."
  @spec drop(t()) :: :ok
  def drop(%Handle{} = h), do: Lifecycle.drop(h)

  # ---- key-value verbs ----

  @doc "The value under `key`, or `repo.table/not_found`. `get(t, key: k)` and `get(t, id: i)` also work."
  @spec get(t(), term(), keyword()) :: {:ok, term()} | {:error, Comn.Errors.ErrorStruct.t()}
  def get(handle, key, opts \\ [])

  def get(%Handle{backend: b, state: s}, [key: key], opts), do: b.get(s, key, opts)

  def get(%Handle{backend: b, state: s}, [id: id], opts) do
    case b.get(s, id, opts) do
      {:ok, %EventStruct{} = e} -> {:ok, e}
      _ -> Comn.Repo.not_found(id)
    end
  end

  def get(%Handle{backend: b, state: s}, key, opts), do: b.get(s, key, opts)

  @doc """
  Stores `value` under `key`. Per-call options (e.g. `schema:`) go to the
  backend. The Repo forms also take them: `set(t, [event: e], schema: S)`.
  """
  @spec set(t(), term(), term(), keyword()) :: :ok | {:error, Comn.Errors.ErrorStruct.t()}
  def set(handle, key, value, opts \\ [])

  def set(%Handle{} = t, [{k, _} | _] = repo_opts, extra, [])
      when k in [:event, :key] and is_list(extra),
      do: set(t, repo_opts ++ extra)

  def set(%Handle{backend: b, state: s}, key, value, opts), do: b.set(s, key, value, opts)

  @doc "Removes `key`. Idempotent."
  @spec delete(t(), term(), keyword()) :: :ok | {:error, Comn.Errors.ErrorStruct.t()}
  def delete(handle, key, opts \\ [])
  def delete(%Handle{backend: b, state: s}, [key: key], opts), do: b.delete(s, key, opts)
  def delete(%Handle{backend: b, state: s}, key, opts), do: b.delete(s, key, opts)

  @doc "All keys."
  @spec keys(t(), keyword()) :: {:ok, [term()]} | {:error, Comn.Errors.ErrorStruct.t()}
  def keys(%Handle{backend: b, state: s}, opts \\ []), do: b.keys(s, opts)

  @doc "Number of entries."
  @spec count(t(), keyword()) :: {:ok, non_neg_integer()} | {:error, Comn.Errors.ErrorStruct.t()}
  def count(%Handle{backend: b, state: s}, opts \\ []), do: b.count(s, opts)

  # ---- @behaviour Comn.Repo ----

  @impl Comn.Repo
  def describe(%Handle{backend: b, state: s, name: name}) do
    with {:ok, n} <- b.count(s, []), do: {:ok, %{name: name, backend: b, count: n}}
  end

  @doc "Repo form of `set`: `set(t, key: k, value: v)` or `set(t, event: e)` (stored under `e.id`)."
  @impl Comn.Repo
  def set(%Handle{} = t, opts) when is_list(opts) do
    cond do
      Comn.Repo.event?(opts) ->
        with {:ok, e} <- Comn.Repo.fetch_event(opts),
             do: set(t, e.id, e, Keyword.delete(opts, :event))

      Keyword.has_key?(opts, :key) ->
        set(
          t,
          Keyword.fetch!(opts, :key),
          Keyword.fetch!(opts, :value),
          Keyword.drop(opts, [:key, :value])
        )

      true ->
        {:error,
         ErrReg.error!("repo.table/invalid_opts", message: "set needs key:/value: or event:")}
    end
  end

  @impl Comn.Repo
  def observe(%Handle{backend: b, state: s}, opts \\ []) do
    with pairs when is_list(pairs) <- b.observe(s, opts) do
      if Comn.Repo.events_view?(opts), do: Comn.Repo.events_in(pairs), else: pairs
    end
  end

  # ---- @behaviour Comn ----

  @impl Comn
  def look,
    do: "Table — key-value repository facade (get/set/delete/keys/count) over fungible backends"

  @impl Comn
  def recon do
    %{
      callbacks: [:open, :close, :drop, :get, :set, :delete, :keys, :count],
      backends: Map.keys(@backends),
      extends: Comn.Repo,
      type: :facade
    }
  end

  @impl Comn
  def choices, do: %{backends: ["ets", "ecto"]}

  @impl Comn
  def act(%{action: :open, name: n, opts: o}), do: open(n, o)
  def act(%{action: :open, name: n}), do: open(n, [])
  def act(input), do: Comn.unknown_action(input)
end
