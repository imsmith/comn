defmodule Comn.TableEctoTest do
  @moduledoc """
  Comn.Repo.Table :ecto backend.

  Four properties on top of the shared Table and event-sink specs:

  1. every mutation is a saga: a transaction with an upsert, and a system
     event on Comn.EventBus saying whether it committed or rolled back
  2. every mutation is against a schema: `schema:` names the Ecto schema
     the data is cast into and upserted; the default is Comn's EventRow
  3. no migrations: the schema module is the declaration and Comn
     converges the database to it on first use
  4. the repository is configuration: a keyword, an `.exs` file, or an
     existing repo module; any Ecto adapter on the code path

  Runs on ecto_sqlite3 over a temp file through the dynamic-repo path.
  """

  use ExUnit.Case, async: true

  # Must precede the conformance `use` lines.
  @moduletag :tmp_dir

  use Comn.TableConformance
  use Comn.EventSinkConformance, backend: Comn.Repo.Table

  alias Comn.Events.EventStruct
  alias Comn.Repo.Table
  alias Comn.Repo.Table.Ecto, as: EctoTable
  alias Comn.Test.SessionRow
  alias Ecto.Adapters.SQL

  @topic "comn.repo.table"

  defp fresh_name, do: :"ecto_table_#{:erlang.unique_integer([:positive])}"
  defp sqlite(dir), do: [adapter: Ecto.Adapters.SQLite3, database: Path.join(dir, "kv.db")]

  def open_table(%{tmp_dir: dir}) do
    {:ok, t} = Table.open(fresh_name(), backend: :ecto, ecto: sqlite(dir))
    {t, fn -> Table.drop(t) end}
  end

  def open_sink(ctx), do: open_table(ctx)

  defp ev(data), do: EventStruct.new(:domain, "table.test", data)

  defp table_exists?(t, source) do
    {:ok, %{rows: rows}} =
      EctoTable.repo(t.state)
      |> SQL.query("SELECT name FROM sqlite_master WHERE type='table' AND name=?", [
        source
      ])

    rows != []
  end

  describe ":ecto repository is configuration" do
    @tag :table_phase2
    test "open/2 needs ecto: or repo:" do
      assert {:error, %Comn.Errors.ErrorStruct{code: "repo.table/invalid_opts"}} =
               Table.open(fresh_name(), backend: :ecto)
    end

    @tag :table_phase2
    test "a keyword config builds and starts a repo for that adapter", %{tmp_dir: dir} do
      {:ok, t} = Table.open(fresh_name(), backend: :ecto, ecto: sqlite(dir))
      repo = EctoTable.repo(t.state)
      assert is_pid(Process.whereis(repo))
      assert repo.__adapter__() == Ecto.Adapters.SQLite3
      Table.drop(t)
    end

    @tag :table_phase2
    test "the same config yields the same running repo", %{tmp_dir: dir} do
      {:ok, a} = Table.open(fresh_name(), backend: :ecto, ecto: sqlite(dir))
      {:ok, b} = Table.open(fresh_name(), backend: :ecto, ecto: sqlite(dir))
      assert EctoTable.repo(a.state) == EctoTable.repo(b.state)
      Table.drop(a)
      Table.drop(b)
    end

    @tag :table_phase2
    test "an .exs file returning the config works too", %{tmp_dir: dir} do
      path = Path.join(dir, "repo.exs")
      File.write!(path, inspect(sqlite(dir)))
      {:ok, t} = Table.open(fresh_name(), backend: :ecto, ecto: path)
      :ok = Table.set(t, :k, :v)
      assert {:ok, :v} = Table.get(t, :k)
      Table.drop(t)
    end

    @tag :table_phase2
    test "an existing repo module is used as is", %{tmp_dir: dir} do
      start_supervised!({Comn.Test.Repo, database: Path.join(dir, "own.db")})
      {:ok, t} = Table.open(fresh_name(), backend: :ecto, repo: Comn.Test.Repo)
      :ok = Table.set(t, :k, :v)
      assert {:ok, :v} = Table.get(t, :k)
      Table.drop(t)
    end

    @tag :table_phase2
    test "data survives close and reopen", %{tmp_dir: dir} do
      name = fresh_name()
      {:ok, t} = Table.open(name, backend: :ecto, ecto: sqlite(dir))
      :ok = Table.set(t, :k, %{durable: true})
      :ok = Table.close(t)
      {:ok, t} = Table.open(name, backend: :ecto, ecto: sqlite(dir))
      assert {:ok, %{durable: true}} = Table.get(t, :k)
      Table.drop(t)
    end
  end

  describe ":ecto converges the schema, no migrations" do
    @tag :table_phase2
    test "the default table appears on first use, named comn_<handle>", %{tmp_dir: dir} do
      name = fresh_name()
      {:ok, t} = Table.open(name, backend: :ecto, ecto: sqlite(dir))
      refute table_exists?(t, "comn_#{name}")
      :ok = Table.set(t, :k, :v)
      assert table_exists?(t, "comn_#{name}")
      Table.drop(t)
    end

    @tag :table_phase2
    test "the default table never collides with a consumer schema's source", %{tmp_dir: dir} do
      {:ok, t} = Table.open(:sessions, backend: :ecto, ecto: sqlite(dir))
      :ok = Table.set(t, :k, :v)
      :ok = Table.set(t, "s1", %{user: "bob", count: 1}, schema: SessionRow)
      assert {:ok, :v} = Table.get(t, :k)
      assert {:ok, %SessionRow{user: "bob"}} = Table.get(t, "s1", schema: SessionRow)
      Table.drop(t)
    end

    @tag :table_phase2
    test "a consumer schema's table appears on first use", %{tmp_dir: dir} do
      {:ok, t} = Table.open(fresh_name(), backend: :ecto, ecto: sqlite(dir))
      refute table_exists?(t, "sessions")
      :ok = Table.set(t, [event: ev(%{user: "ian", count: 1})], schema: SessionRow)
      assert table_exists?(t, "sessions")
      Table.drop(t)
    end

    @tag :table_phase2
    test "converging twice is a no-op", %{tmp_dir: dir} do
      {:ok, t} = Table.open(fresh_name(), backend: :ecto, ecto: sqlite(dir))
      :ok = Table.set(t, :a, 1)
      :ok = Table.set(t, :b, 2)
      assert {:ok, 2} = Table.count(t)
      Table.drop(t)
    end

    @tag :table_phase2
    test "there is no schema_migrations table", %{tmp_dir: dir} do
      {:ok, t} = Table.open(fresh_name(), backend: :ecto, ecto: sqlite(dir))
      :ok = Table.set(t, :k, :v)
      refute table_exists?(t, "schema_migrations")
      Table.drop(t)
    end
  end

  describe ":ecto every mutation is against a schema" do
    setup ctx, do: %{t: open!(ctx)}

    @tag :table_phase2
    test "set/2 with schema: upserts the event's data into that schema", %{t: t} do
      e = ev(%{user: "ian", count: 1})
      :ok = Table.set(t, [event: e], schema: SessionRow)

      assert {:ok, %SessionRow{id: id, user: "ian", count: 1}} =
               Table.get(t, e.id, schema: SessionRow)

      assert id == e.id
    end

    @tag :table_phase2
    test "a second set with the same key is an upsert, not a duplicate", %{t: t} do
      e = ev(%{user: "ian", count: 1})
      :ok = Table.set(t, [event: e], schema: SessionRow)
      :ok = Table.set(t, [event: %{e | data: %{user: "ian", count: 2}}], schema: SessionRow)
      assert {:ok, %SessionRow{count: 2}} = Table.get(t, e.id, schema: SessionRow)
      assert {:ok, 1} = Table.count(t, schema: SessionRow)
    end

    @tag :table_phase2
    test "set/4 with a key and a map of attrs also works against a schema", %{t: t} do
      :ok = Table.set(t, "s1", %{user: "bob", count: 3}, schema: SessionRow)

      assert {:ok, %SessionRow{id: "s1", user: "bob", count: 3}} =
               Table.get(t, "s1", schema: SessionRow)

      assert {:ok, ["s1"]} = Table.keys(t, schema: SessionRow)
      assert [{"s1", %SessionRow{}}] = Table.observe(t, schema: SessionRow)
    end

    @tag :table_phase2
    test "the default schema is the event itself", %{t: t} do
      e = ev(%{n: 1})
      :ok = Table.set(t, event: e)
      assert {:ok, ^e} = Table.get(t, id: e.id)
      assert {:ok, ^e} = Table.get(t, e.id)
    end

    @tag :table_phase2
    test "delete/3 with schema: removes the row", %{t: t} do
      :ok = Table.set(t, "s1", %{user: "bob", count: 3}, schema: SessionRow)
      assert :ok = Table.delete(t, "s1", schema: SessionRow)

      assert {:error, %Comn.Errors.ErrorStruct{code: "repo.table/not_found"}} =
               Table.get(t, "s1", schema: SessionRow)
    end
  end

  describe ":ecto every mutation is a saga" do
    setup ctx do
      {:ok, _} = Comn.EventBus.subscribe(@topic)
      %{t: open!(ctx)}
    end

    @tag :table_phase2
    test "a committed set emits a system event", %{t: t} do
      name = t.name
      :ok = Table.set(t, :k, :v)

      assert_receive {:event, @topic,
                      %EventStruct{
                        type: :system,
                        topic: "repo.table.set",
                        data: %{name: ^name, key: :k, status: :ok}
                      }}
    end

    @tag :table_phase2
    test "a failed set rolls back, returns set_failed, and emits a failed event", %{t: t} do
      name = t.name
      e = ev(%{user: "ian", count: "not a number"})

      assert {:error, %Comn.Errors.ErrorStruct{code: "repo.table/set_failed"}} =
               Table.set(t, [event: e], schema: SessionRow)

      id = e.id

      assert_receive {:event, @topic,
                      %EventStruct{
                        type: :system,
                        topic: "repo.table.set",
                        data: %{name: ^name, key: ^id, status: :failed}
                      }}

      assert {:error, %Comn.Errors.ErrorStruct{code: "repo.table/not_found"}} =
               Table.get(t, e.id, schema: SessionRow)
    end

    @tag :table_phase2
    test "a database error inside the saga is a rollback, not an exception", %{t: t} do
      :ok = Table.set(t, "s1", %{user: "bob", count: 1}, schema: SessionRow)
      assert_receive {:event, @topic, %EventStruct{data: %{status: :ok}}}

      assert {:error, %Comn.Errors.ErrorStruct{code: "repo.table/set_failed"}} =
               Table.set(t, "s2", %{user: "eve", extra: "x"}, schema: Comn.Test.BrokenRow)

      assert_receive {:event, @topic,
                      %EventStruct{topic: "repo.table.set", data: %{key: "s2", status: :failed}}}

      assert {:error, _} = Table.get(t, "s2", schema: SessionRow)
    end

    @tag :table_phase2
    test "a delete emits too", %{t: t} do
      :ok = Table.set(t, :k, :v)
      assert_receive {:event, @topic, %EventStruct{topic: "repo.table.set"}}
      :ok = Table.delete(t, :k)

      assert_receive {:event, @topic,
                      %EventStruct{topic: "repo.table.delete", data: %{key: :k, status: :ok}}}
    end
  end
end
