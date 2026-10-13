defmodule Comn.Repo.Stream.SQLite do
  @moduledoc """
  SQLite-backed durable implementation of `Comn.Repo.Stream`.

  One GenServer per open stream, registered under the stream name,
  owns the database connection and serialises every append. Events are
  stored as `term_to_binary` blobs keyed by an autoincrement integer
  offset, so offsets are monotonic, start at 1, and are never reused —
  even across reopen. Consumer-group positions live in a second table
  in the same file.

  Because every append passes through one process, live subscribers
  always see offsets in order from this backend.

  ## Lifecycle

  - `open/2` creates the file if missing or reopens it with its data.
    The process is **not** linked to the caller; it lives until `close/1`
    or `drop/1`. To tie it to a supervision tree instead, use the child
    spec: `{Comn.Repo.Stream.SQLite, name: :audit, path: "/var/lib/app/audit.db"}`.
  - `close/1` stops the process and keeps the file.
  - `drop/1` stops the process and deletes the file.

  ## Examples

      iex> name = String.to_atom("sqlite_doc_#{:erlang.unique_integer([:positive])}")
      iex> path = Path.join(System.tmp_dir!(), "\#{name}.db")
      iex> :ok = Comn.Repo.Stream.SQLite.open(name, path: path)
      iex> event = Comn.Events.EventStruct.new(:test, "doc.example", %{})
      iex> {:ok, offset} = Comn.Repo.Stream.SQLite.append(name, event)
      iex> :ok = Comn.Repo.Stream.SQLite.close(name)
      iex> :ok = Comn.Repo.Stream.SQLite.open(name, path: path)
      iex> {:ok, ^offset} = Comn.Repo.Stream.SQLite.head(name)
      iex> Comn.Repo.Stream.SQLite.drop(name)
      :ok
  """

  @behaviour Comn
  @behaviour Comn.Repo
  @behaviour Comn.Repo.Stream

  use GenServer

  alias Comn.Errors.Registry, as: ErrReg
  alias Comn.Events.EventStruct
  alias Exqlite.Sqlite3

  # Subscribers share the Comn.EventBus registry with Mem, keyed {:stream, name}.
  @registry Comn.EventBus

  # Lifecycle

  @doc """
  Opens (creating if needed) the stream stored at `opts[:path]` under `name`.

  The process is not linked to the caller. Errors: `repo.stream/invalid_opts`
  (no path), `repo.stream/already_exists`.
  """
  @spec open(atom(), keyword()) :: :ok | {:error, Comn.Errors.ErrorStruct.t()}
  def open(name, opts) when is_atom(name) and is_list(opts) do
    start(name, opts, &GenServer.start/3) |> started()
  end

  @doc """
  Supervisor entry point: `start_link(name: :audit, path: "/abs/audit.db")`.
  Same as `open/2` but linked, for use in a child spec.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    start(Keyword.fetch!(opts, :name), opts, &GenServer.start_link/3)
  end

  defp start(name, opts, starter) do
    case Keyword.fetch(opts, :path) do
      {:ok, path} when is_binary(path) ->
        starter.(__MODULE__, {name, path}, name: name)

      _ ->
        {:error,
         ErrReg.error!("repo.stream/invalid_opts",
           field: "path",
           suggestion: "pass path: \"/abs/file.db\""
         )}
    end
  end

  defp started({:ok, _pid}), do: :ok

  defp started({:error, {:already_started, _}}),
    do: {:error, ErrReg.error!("repo.stream/already_exists")}

  defp started({:error, %Comn.Errors.ErrorStruct{} = err}), do: {:error, err}

  @doc "Stops the stream process. The file is kept. Idempotent."
  @spec close(atom()) :: :ok
  def close(name) when is_atom(name) do
    case Process.whereis(name) do
      nil -> :ok
      pid -> GenServer.stop(pid)
    end
  end

  @doc "Stops the stream process and deletes its file. Idempotent."
  @spec drop(atom()) :: :ok
  def drop(name) when is_atom(name) do
    case Process.whereis(name) do
      nil ->
        :ok

      pid ->
        try do
          path = GenServer.call(pid, :path)
          :ok = GenServer.stop(pid)
          for suffix <- ["", "-wal", "-shm"], do: File.rm(path <> suffix)
          :ok
        catch
          # died between whereis and the call; nothing left to stop
          :exit, _ -> :ok
        end
    end
  end

  # Comn.Repo.Stream

  @impl Comn.Repo.Stream
  def append(name, %EventStruct{} = event) when is_atom(name) do
    call(name, {:append, [event]}) |> unwrap_single()
  end

  def append(name, _not_event) when is_atom(name) do
    with :ok <- ensure_running(name), do: {:error, ErrReg.error!("repo.stream/invalid_event")}
  end

  @impl Comn.Repo.Stream
  def append_many(name, events) when is_atom(name) and is_list(events) do
    with :ok <- ensure_running(name),
         :ok <- validate_events(events) do
      call(name, {:append, events})
    end
  end

  @impl Comn.Repo.Stream
  def read(name, cursor, count) when is_atom(name) and is_integer(count) and count > 0 do
    call(name, {:read, cursor, count})
  end

  @impl Comn.Repo.Stream
  def head(name) when is_atom(name), do: call(name, :head)

  @impl Comn.Repo.Stream
  def tail(name) when is_atom(name), do: call(name, :tail)

  @impl Comn.Repo.Stream
  def subscribe(name, _opts) when is_atom(name) do
    with :ok <- ensure_running(name) do
      ref = make_ref()
      {:ok, _owner} = Registry.register(@registry, {:stream, name}, ref)
      {:ok, ref}
    end
  end

  @impl Comn.Repo.Stream
  def unsubscribe(name, ref) when is_atom(name) and is_reference(ref) do
    Registry.unregister_match(@registry, {:stream, name}, ref)
  end

  @impl Comn.Repo.Stream
  def commit(name, group, offset) when is_atom(name), do: call(name, {:commit, group, offset})

  @impl Comn.Repo.Stream
  def position(name, group) when is_atom(name), do: call(name, {:position, group})

  # Comn.Repo

  @impl Comn.Repo
  def describe(name) when is_atom(name), do: call(name, :describe)

  @impl Comn.Repo
  def get(name, id: id) when is_atom(name) do
    case Enum.find(observe(name, as: :events), &(&1.id == id)) do
      nil -> Comn.Repo.not_found(id)
      e -> {:ok, e}
    end
  end

  def get(name, opts) when is_atom(name) and is_list(opts) do
    call(name, {:get, Keyword.get(opts, :offset)})
  end

  @impl Comn.Repo
  def set(name, opts) when is_atom(name) and is_list(opts) do
    case Keyword.fetch(opts, :event) do
      {:ok, event} -> append(name, event)
      :error -> {:error, ErrReg.error!("repo.stream/invalid_event")}
    end
  end

  @impl Comn.Repo
  def delete(_name, _opts), do: {:error, ErrReg.error!("repo.stream/append_only")}

  @impl Comn.Repo
  def observe(name, opts) when is_atom(name) and is_list(opts) do
    pairs = observe_pairs(name)
    if Comn.Repo.events_view?(opts), do: Stream.map(pairs, &elem(&1, 1)), else: pairs
  end

  defp observe_pairs(name) do
    Stream.resource(
      fn -> :head end,
      fn
        :done ->
          {:halt, nil}

        cursor ->
          case read(name, cursor, 100) do
            {:ok, []} -> {:halt, nil}
            {:ok, batch} -> {batch, elem(List.last(batch), 0) + 1}
            {:error, _} -> {:halt, nil}
          end
      end,
      fn _ -> :ok end
    )
  end

  # Comn

  @impl Comn
  def look, do: "Stream.SQLite — SQLite-backed durable append-only stream"

  @impl Comn
  def recon do
    %{type: :implementation, implements: Comn.Repo.Stream, backend: :sqlite, durable?: true}
  end

  @impl Comn
  def choices do
    %{
      actions: [
        :open,
        :close,
        :drop,
        :append,
        :read,
        :head,
        :tail,
        :subscribe,
        :unsubscribe,
        :commit,
        :position
      ],
      cursors: [:head, :tail, :offset],
      opts: [path: "absolute path to the .db file"]
    }
  end

  @impl Comn
  def act(%{action: :open, name: n, path: p}), do: {:ok, open(n, path: p)}
  def act(%{action: :close, name: n}), do: {:ok, close(n)}
  def act(%{action: :drop, name: n}), do: {:ok, drop(n)}
  def act(%{action: :append, name: n, event: e}), do: append(n, e)
  def act(%{action: :read, name: n, from: f, count: c}), do: read(n, f, c)
  def act(%{action: :head, name: n}), do: head(n)
  def act(%{action: :tail, name: n}), do: tail(n)
  def act(%{action: :subscribe, name: n}), do: subscribe(n, [])
  def act(%{action: :unsubscribe, name: n, ref: r}), do: {:ok, unsubscribe(n, r)}
  def act(%{action: :commit, name: n, group: g, offset: o}), do: commit(n, g, o)
  def act(%{action: :position, name: n, group: g}), do: position(n, g)
  def act(input), do: Comn.unknown_action(input)

  # GenServer

  @impl GenServer
  def init({name, path}) do
    File.mkdir_p!(Path.dirname(path))
    {:ok, db} = Sqlite3.open(path)
    :ok = Sqlite3.execute(db, "PRAGMA journal_mode = WAL;")
    :ok = Sqlite3.execute(db, "PRAGMA synchronous = NORMAL;")

    :ok =
      Sqlite3.execute(db, """
        CREATE TABLE IF NOT EXISTS events (
          offset INTEGER PRIMARY KEY AUTOINCREMENT,
          event  BLOB NOT NULL
        );
      """)

    :ok =
      Sqlite3.execute(db, """
        CREATE TABLE IF NOT EXISTS groups (
          grp    BLOB PRIMARY KEY,
          offset INTEGER NOT NULL
        );
      """)

    {:ok, %{name: name, path: path, db: db}}
  end

  @impl GenServer
  def terminate(_reason, %{db: db}) do
    _ = Sqlite3.close(db)
    :ok
  end

  @impl GenServer
  def handle_call(:path, _from, s), do: {:reply, s.path, s}

  def handle_call({:append, events}, _from, %{db: db, name: name} = s) do
    offsets =
      Enum.map(events, fn event ->
        exec(db, "INSERT INTO events (event) VALUES (?);", [
          {:blob, :erlang.term_to_binary(event)}
        ])

        [[offset]] = rows(db, "SELECT last_insert_rowid();", [])
        notify(name, offset, event)
        offset
      end)

    {:reply, {:ok, offsets}, s}
  end

  def handle_call({:read, :head, n}, _from, %{db: db} = s) do
    {:reply, {:ok, select_events(db, "ORDER BY offset ASC LIMIT ?", [n])}, s}
  end

  def handle_call({:read, :tail, n}, _from, %{db: db} = s) do
    {:reply, {:ok, select_events(db, "ORDER BY offset DESC LIMIT ?", [n]) |> Enum.reverse()}, s}
  end

  def handle_call({:read, offset, n}, _from, %{db: db} = s) when is_integer(offset) do
    {:reply,
     {:ok, select_events(db, "WHERE offset >= ? ORDER BY offset ASC LIMIT ?", [offset, n])}, s}
  end

  def handle_call({:read, bad, _n}, _from, s) do
    {:reply, {:error, ErrReg.error!("repo.stream/invalid_offset", field: inspect(bad))}, s}
  end

  def handle_call(:head, _from, %{db: db} = s),
    do: {:reply, {:ok, scalar(db, "SELECT MAX(offset) FROM events;")}, s}

  def handle_call(:tail, _from, %{db: db} = s),
    do: {:reply, {:ok, scalar(db, "SELECT MIN(offset) FROM events;")}, s}

  def handle_call(:describe, _from, %{db: db, name: name} = s) do
    reply = %{
      name: name,
      head: scalar(db, "SELECT MAX(offset) FROM events;"),
      tail: scalar(db, "SELECT MIN(offset) FROM events;"),
      count: scalar(db, "SELECT COUNT(*) FROM events;")
    }

    {:reply, {:ok, reply}, s}
  end

  def handle_call({:get, offset}, _from, %{db: db} = s) do
    reply =
      case select_events(db, "WHERE offset = ?", [offset]) do
        [{_o, event}] -> {:ok, event}
        [] -> {:error, ErrReg.error!("repo.stream/invalid_offset", field: inspect(offset))}
      end

    {:reply, reply, s}
  end

  def handle_call({:commit, group, offset}, _from, %{db: db} = s) do
    reply =
      if is_integer(offset) and rows(db, "SELECT 1 FROM events WHERE offset = ?;", [offset]) != [] do
        exec(db, "INSERT OR REPLACE INTO groups (grp, offset) VALUES (?, ?);", [
          {:blob, :erlang.term_to_binary(group)},
          offset
        ])

        :ok
      else
        {:error, ErrReg.error!("repo.stream/invalid_offset", field: inspect(offset))}
      end

    {:reply, reply, s}
  end

  def handle_call({:position, group}, _from, %{db: db} = s) do
    reply =
      case rows(db, "SELECT offset FROM groups WHERE grp = ?;", [
             {:blob, :erlang.term_to_binary(group)}
           ]) do
        [[offset]] -> {:ok, offset}
        [] -> {:ok, nil}
      end

    {:reply, reply, s}
  end

  # Internals

  defp call(name, msg) do
    with :ok <- ensure_running(name), do: GenServer.call(name, msg)
  end

  defp unwrap_single({:ok, [offset]}), do: {:ok, offset}
  defp unwrap_single(other), do: other

  defp ensure_running(name) do
    case Process.whereis(name) do
      nil -> {:error, ErrReg.error!("repo.stream/not_found", field: name)}
      _ -> :ok
    end
  end

  defp validate_events(events) do
    if Enum.all?(events, &match?(%EventStruct{}, &1)),
      do: :ok,
      else: {:error, ErrReg.error!("repo.stream/invalid_event")}
  end

  defp notify(name, offset, event) do
    Registry.dispatch(@registry, {:stream, name}, fn entries ->
      for {pid, _ref} <- entries, do: send(pid, {:stream, name, offset, event})
    end)
  end

  defp select_events(db, clause, params) do
    for [offset, blob] <- rows(db, "SELECT offset, event FROM events " <> clause <> ";", params) do
      {offset, :erlang.binary_to_term(blob, [:safe])}
    end
  end

  defp scalar(db, sql) do
    [[value]] = rows(db, sql, [])
    value
  end

  defp exec(db, sql, params) do
    {:ok, stmt} = Sqlite3.prepare(db, sql)
    :ok = Sqlite3.bind(stmt, params)
    :done = Sqlite3.step(db, stmt)
    :ok = Sqlite3.release(db, stmt)
  end

  defp rows(db, sql, params) do
    {:ok, stmt} = Sqlite3.prepare(db, sql)
    :ok = Sqlite3.bind(stmt, params)
    result = collect(db, stmt, [])
    :ok = Sqlite3.release(db, stmt)
    result
  end

  defp collect(db, stmt, acc) do
    case Sqlite3.step(db, stmt) do
      :done -> Enum.reverse(acc)
      {:row, row} -> collect(db, stmt, [row | acc])
    end
  end
end
