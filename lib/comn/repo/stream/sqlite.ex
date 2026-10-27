defmodule Comn.Repo.Stream.SQLite do
  @moduledoc false
  # SQLite-backed durable stream backend. One GenServer per open stream,
  # registered under the stream name, owns the exqlite connection and
  # serialises every append (so live delivery is in order). Events are
  # term_to_binary blobs keyed by an AUTOINCREMENT offset: monotonic from 1,
  # never reused across reopen. open/2 creates or reopens the file; close/1
  # stops the process and keeps the file; drop/1 deletes it. The process is
  # not linked to the opener; start_link/1 is the supervisor entry.

  @behaviour Comn.Repo.Stream.Backend

  use GenServer

  alias Comn.Errors.Registry, as: ErrReg
  alias Exqlite.Sqlite3

  # ---- Backend ----

  @impl Comn.Repo.Stream.Backend
  def open(name, opts) when is_atom(name) do
    case start(name, opts, &GenServer.start/3) do
      {:ok, _pid} ->
        {:ok, name}

      {:error, {:already_started, _}} ->
        {:error, ErrReg.error!("repo.stream/already_exists", field: name)}

      {:error, %Comn.Errors.ErrorStruct{} = err} ->
        {:error, err}

      {:error, reason} ->
        {:error, ErrReg.error!("repo.stream/backend_error", message: inspect(reason))}
    end
  end

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts),
    do: start(Keyword.fetch!(opts, :name), opts, &GenServer.start_link/3)

  @impl Comn.Repo.Stream.Backend
  def close(name) do
    case Process.whereis(name) do
      nil -> :ok
      pid -> GenServer.stop(pid)
    end
  end

  @impl Comn.Repo.Stream.Backend
  def drop(name) do
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

  @impl Comn.Repo.Stream.Backend
  def append(name, events), do: call(name, {:append, events})

  @impl Comn.Repo.Stream.Backend
  def read(name, cursor, count), do: call(name, {:read, cursor, count})

  @impl Comn.Repo.Stream.Backend
  def head(name), do: call(name, :head)

  @impl Comn.Repo.Stream.Backend
  def tail(name), do: call(name, :tail)

  @impl Comn.Repo.Stream.Backend
  def count(name), do: call(name, :count)

  @impl Comn.Repo.Stream.Backend
  def subscribe(name), do: ensure_running(name)

  # ---- GenServer ----

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
        Comn.Repo.Stream.notify(name, offset, event)
        offset
      end)

    {:reply, {:ok, offsets}, s}
  end

  def handle_call({:read, :head, n}, _from, %{db: db} = s) do
    {:reply, {:ok, select_events(db, "ORDER BY offset ASC LIMIT ?", [n])}, s}
  end

  def handle_call({:read, :tail, n}, _from, %{db: db} = s) do
    {:reply, {:ok, Enum.reverse(select_events(db, "ORDER BY offset DESC LIMIT ?", [n]))}, s}
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

  def handle_call(:count, _from, %{db: db} = s),
    do: {:reply, {:ok, scalar(db, "SELECT COUNT(*) FROM events;")}, s}

  # ---- internals ----

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

  defp call(name, msg) do
    with :ok <- ensure_running(name), do: GenServer.call(name, msg)
  end

  defp ensure_running(name) do
    case Process.whereis(name) do
      nil -> {:error, ErrReg.error!("repo.stream/not_found", field: name)}
      _ -> :ok
    end
  end

  defp select_events(db, clause, params) do
    for [offset, blob] <- rows(db, "SELECT offset, event FROM events " <> clause <> ";", params) do
      {offset, Comn.Repo.decode_term(blob)}
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
