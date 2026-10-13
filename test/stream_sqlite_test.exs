defmodule Comn.StreamSQLiteTest do
  @moduledoc """
  Phase 3: SQLite-backed durable stream.

  Runs the shared conformance spec, then the lifecycle and durability
  tests that only make sense for a file-backed stream.

  To run:
    mix test test/stream_sqlite_test.exs
  """

  use ExUnit.Case, async: true
  use Comn.StreamConformance, backend: Comn.Repo.Stream.SQLite

  @moduletag :tmp_dir

  doctest Comn.Repo.Stream.SQLite

  alias Comn.Repo.Stream.SQLite

  defp fresh_name, do: :"sqlite_stream_#{:erlang.unique_integer([:positive])}"

  def open_stream(%{tmp_dir: dir}) do
    name = fresh_name()
    :ok = SQLite.open(name, path: Path.join(dir, "#{name}.db"))
    {name, fn -> SQLite.drop(name) end}
  end

  describe "SQLite lifecycle" do
    @tag :stream_phase3
    test "open/2 requires a :path", %{tmp_dir: _} do
      assert {:error, %Comn.Errors.ErrorStruct{code: "repo.stream/invalid_opts"}} =
               SQLite.open(fresh_name(), [])
    end

    @tag :stream_phase3
    test "open/2 twice under the same name returns already_exists", %{tmp_dir: dir} do
      name = fresh_name()
      path = Path.join(dir, "dup.db")
      :ok = SQLite.open(name, path: path)

      assert {:error, %Comn.Errors.ErrorStruct{code: "repo.stream/already_exists"}} =
               SQLite.open(name, path: path)

      SQLite.drop(name)
    end

    @tag :stream_phase3
    test "open/2 creates parent directories", %{tmp_dir: dir} do
      name = fresh_name()
      path = Path.join([dir, "nested", "deeper", "s.db"])
      assert :ok = SQLite.open(name, path: path)
      assert File.exists?(path)
      SQLite.drop(name)
    end

    @tag :stream_phase3
    test "close/1 stops the stream and keeps the file", %{tmp_dir: dir} do
      name = fresh_name()
      path = Path.join(dir, "keep.db")
      :ok = SQLite.open(name, path: path)
      assert :ok = SQLite.close(name)
      assert {:error, %Comn.Errors.ErrorStruct{code: "repo.stream/not_found"}} = SQLite.head(name)
      assert File.exists?(path)
      assert :ok = SQLite.close(name)
    end

    @tag :stream_phase3
    test "drop/1 stops the stream and deletes the file", %{tmp_dir: dir} do
      name = fresh_name()
      path = Path.join(dir, "gone.db")
      :ok = SQLite.open(name, path: path)
      assert :ok = SQLite.drop(name)
      refute File.exists?(path)
      assert :ok = SQLite.drop(name)
    end
  end

  describe "SQLite durability" do
    @tag :stream_phase3
    test "events, offsets and group positions survive close and reopen", %{tmp_dir: dir} do
      name = fresh_name()
      path = Path.join(dir, "durable.db")
      :ok = SQLite.open(name, path: path)

      {:ok, [o1, o2, o3]} = SQLite.append_many(name, Enum.map(1..3, &event(%{n: &1})))
      :ok = SQLite.commit(name, :billing, o2)
      :ok = SQLite.close(name)

      :ok = SQLite.open(name, path: path)
      assert {:ok, ^o3} = SQLite.head(name)
      assert {:ok, ^o1} = SQLite.tail(name)
      assert {:ok, ^o2} = SQLite.position(name, :billing)

      {:ok, events} = SQLite.read(name, :head, 10)
      assert Enum.map(events, fn {_o, e} -> e.data.n end) == [1, 2, 3]

      # offsets keep climbing after reopen; nothing is reused
      {:ok, o4} = SQLite.append(name, event(%{n: 4}))
      assert o4 > o3
      SQLite.drop(name)
    end

    @tag :stream_phase3
    test "the same file can be reopened under a different name", %{tmp_dir: dir} do
      path = Path.join(dir, "rename.db")
      a = fresh_name()
      :ok = SQLite.open(a, path: path)
      {:ok, o} = SQLite.append(a, event(%{n: 1}))
      :ok = SQLite.close(a)

      b = fresh_name()
      :ok = SQLite.open(b, path: path)
      assert {:ok, ^o} = SQLite.head(b)
      SQLite.drop(b)
    end

    @tag :stream_phase3
    test "subscribers are delivered in append order from one serialised writer", %{tmp_dir: dir} do
      name = fresh_name()
      :ok = SQLite.open(name, path: Path.join(dir, "order.db"))
      {:ok, _} = SQLite.subscribe(name, [])

      tasks =
        for n <- 1..20 do
          Task.async(fn -> SQLite.append(name, event(%{n: n})) end)
        end

      Enum.each(tasks, &Task.await/1)

      offsets =
        for _ <- 1..20 do
          receive do
            {:stream, ^name, o, _} -> o
          after
            500 -> flunk("missing live message")
          end
        end

      assert offsets == Enum.sort(offsets)
      SQLite.drop(name)
    end
  end
end
