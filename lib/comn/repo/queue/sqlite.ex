defmodule Comn.Repo.Queue.SQLite do
  @moduledoc false
  # SQLite-backed durable queue. Items live in a single file; one
  # GenServer per open queue serializes access. Reservations are
  # tracked in-row so a clean shutdown is enough to leave the queue
  # consistent. On re-open, any reservation whose `reserved_by` PID
  # is no longer alive (or is from a previous BEAM run) is cleared.

  @behaviour Comn.Repo.Queue.Backend

  use GenServer

  alias Comn.Errors.Registry, as: ErrReg
  alias Exqlite.Sqlite3

  defmodule State do
    @moduledoc false
    @enforce_keys [:db, :discipline, :path]
    defstruct [:db, :discipline, :path]
  end

  # ---- Backend callbacks ----

  @impl true
  def open(name, opts) do
    case Keyword.fetch(opts, :path) do
      {:ok, path} when is_binary(path) ->
        discipline = Keyword.get(opts, :discipline, :fifo)
        GenServer.start_link(__MODULE__, {name, path, discipline})

      _ ->
        {:error,
         ErrReg.error!("repo.queue/invalid_opts",
           field: "path",
           suggestion: "absolute path to the queue file is required for :sqlite"
         )}
    end
  end

  @impl true
  def close(pid) do
    if Process.alive?(pid), do: GenServer.stop(pid, :normal), else: :ok
  end

  @impl true
  def push(pid, item), do: GenServer.call(pid, {:push, item})
  @impl true
  def reserve(pid), do: GenServer.call(pid, :reserve)
  @impl true
  def ack(pid, token), do: GenServer.call(pid, {:ack, token})
  @impl true
  def release(pid, token), do: GenServer.call(pid, {:release, token})
  @impl true
  def peek(pid, n), do: GenServer.call(pid, {:peek, n})
  @impl true
  def size(pid), do: GenServer.call(pid, :size)
  @impl true
  def find(pid, fun), do: GenServer.call(pid, {:find, fun})
  @impl true
  def remove(pid, fun), do: GenServer.call(pid, {:remove, fun})

  # ---- GenServer ----

  @impl true
  def init({_name, path, discipline}) do
    File.mkdir_p!(Path.dirname(path))
    {:ok, db} = Sqlite3.open(path)
    :ok = Sqlite3.execute(db, "PRAGMA journal_mode = WAL;")
    :ok = Sqlite3.execute(db, "PRAGMA synchronous = NORMAL;")

    :ok =
      Sqlite3.execute(db, """
        CREATE TABLE IF NOT EXISTS items (
          id          INTEGER PRIMARY KEY AUTOINCREMENT,
          payload     BLOB    NOT NULL,
          inserted_at INTEGER NOT NULL,
          reserved_at INTEGER,
          reserved_by TEXT
        );
      """)

    :ok =
      Sqlite3.execute(
        db,
        "CREATE INDEX IF NOT EXISTS idx_items_available ON items(reserved_at, id);"
      )

    # Reap stale reservations: any row with a non-null reserved_at is
    # left over from a previous run, since this process is brand new.
    :ok =
      Sqlite3.execute(
        db,
        "UPDATE items SET reserved_at = NULL, reserved_by = NULL WHERE reserved_at IS NOT NULL;"
      )

    {:ok, %State{db: db, discipline: discipline, path: path}}
  end

  @impl true
  def terminate(_reason, %State{db: db}) do
    _ = Sqlite3.close(db)
    :ok
  end

  @impl true
  def handle_call({:push, item}, _from, %State{db: db} = s) do
    payload = :erlang.term_to_binary(item)
    now = System.system_time(:millisecond)
    {:ok, stmt} = Sqlite3.prepare(db, "INSERT INTO items (payload, inserted_at) VALUES (?, ?);")
    :ok = Sqlite3.bind(stmt, [{:blob, payload}, now])
    :done = Sqlite3.step(db, stmt)
    :ok = Sqlite3.release(db, stmt)
    {:reply, :ok, s}
  end

  def handle_call(:reserve, _from, %State{db: db, discipline: d} = s) do
    order = if d == :fifo, do: "ASC", else: "DESC"

    select_sql =
      "SELECT id, payload FROM items WHERE reserved_at IS NULL ORDER BY id #{order} LIMIT 1;"

    case fetch_one(db, select_sql, []) do
      :empty ->
        {:reply, :empty, s}

      {:ok, row} ->
        [id, payload] = row
        item = :erlang.binary_to_term(payload)
        now = System.system_time(:millisecond)
        pid_str = inspect(self())

        {:ok, stmt} =
          Sqlite3.prepare(db, "UPDATE items SET reserved_at = ?, reserved_by = ? WHERE id = ?;")

        :ok = Sqlite3.bind(stmt, [now, pid_str, id])
        :done = Sqlite3.step(db, stmt)
        :ok = Sqlite3.release(db, stmt)

        {:reply, {:ok, {id, item}}, s}
    end
  end

  def handle_call({:ack, id}, _from, %State{db: db} = s) do
    {:ok, stmt} = Sqlite3.prepare(db, "DELETE FROM items WHERE id = ?;")
    :ok = Sqlite3.bind(stmt, [id])
    :done = Sqlite3.step(db, stmt)
    :ok = Sqlite3.release(db, stmt)
    {:reply, :ok, s}
  end

  def handle_call({:release, id}, _from, %State{db: db} = s) do
    {:ok, stmt} =
      Sqlite3.prepare(
        db,
        "UPDATE items SET reserved_at = NULL, reserved_by = NULL WHERE id = ?;"
      )

    :ok = Sqlite3.bind(stmt, [id])
    :done = Sqlite3.step(db, stmt)
    :ok = Sqlite3.release(db, stmt)
    {:reply, :ok, s}
  end

  def handle_call({:peek, n}, _from, %State{db: db, discipline: d} = s) do
    order = if d == :fifo, do: "ASC", else: "DESC"
    sql = "SELECT payload FROM items WHERE reserved_at IS NULL ORDER BY id #{order} LIMIT ?;"
    items = fetch_all(db, sql, [n]) |> Enum.map(fn [payload] -> :erlang.binary_to_term(payload) end)
    {:reply, items, s}
  end

  def handle_call(:size, _from, %State{db: db} = s) do
    count =
      case fetch_all(db, "SELECT COUNT(*) FROM items;", []) do
        [] -> 0
        [[n]] -> n
      end

    {:reply, count, s}
  end

  def handle_call({:find, fun}, _from, %State{db: db, discipline: d} = s) do
    {:reply, do_find(db, d, fun, :find), s}
  end

  def handle_call({:remove, fun}, _from, %State{db: db, discipline: d} = s) do
    {:reply, do_find(db, d, fun, :remove), s}
  end

  # ---- helpers ----

  defp do_find(db, discipline, fun, mode) do
    order = if discipline == :fifo, do: "ASC", else: "DESC"
    sql = "SELECT id, payload FROM items WHERE reserved_at IS NULL ORDER BY id #{order};"

    Enum.reduce_while(fetch_all(db, sql, []), :not_found, fn [id, payload], _ ->
      item = :erlang.binary_to_term(payload)

      if fun.(item) do
        if mode == :remove do
          {:ok, stmt} = Sqlite3.prepare(db, "DELETE FROM items WHERE id = ?;")
          :ok = Sqlite3.bind(stmt, [id])
          :done = Sqlite3.step(db, stmt)
          :ok = Sqlite3.release(db, stmt)
        end

        {:halt, {:ok, item}}
      else
        {:cont, :not_found}
      end
    end)
  end

  defp fetch_one(db, sql, params) do
    {:ok, stmt} = Sqlite3.prepare(db, sql)
    :ok = Sqlite3.bind(stmt, params)

    result =
      case Sqlite3.step(db, stmt) do
        :done -> :empty
        {:row, row} -> {:ok, row}
      end

    :ok = Sqlite3.release(db, stmt)
    result
  end

  defp fetch_all(db, sql, params) do
    {:ok, stmt} = Sqlite3.prepare(db, sql)
    :ok = Sqlite3.bind(stmt, params)
    rows = collect(db, stmt, [])
    :ok = Sqlite3.release(db, stmt)
    rows
  end

  defp collect(db, stmt, acc) do
    case Sqlite3.step(db, stmt) do
      :done -> Enum.reverse(acc)
      {:row, row} -> collect(db, stmt, [row | acc])
    end
  end
end
