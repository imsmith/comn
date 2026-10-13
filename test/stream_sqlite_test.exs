defmodule Comn.StreamSQLiteTest do
  @moduledoc """
  Phase 3: :sqlite durable stream backend, through the facade.

  To run:
    mix test test/stream_sqlite_test.exs
  """

  use ExUnit.Case, async: true

  # Must precede the conformance `use` lines: module tags only reach tests
  # defined after them.
  @moduletag :tmp_dir

  use Comn.StreamConformance
  use Comn.EventSinkConformance, backend: Comn.Repo.Stream

  alias Comn.Repo.Stream

  defp fresh_name, do: :"sqlite_stream_#{:erlang.unique_integer([:positive])}"

  def open_stream(%{tmp_dir: dir}) do
    name = fresh_name()
    {:ok, s} = Stream.open(name, backend: :sqlite, path: Path.join(dir, "#{name}.db"))
    {s, fn -> Stream.drop(s) end}
  end

  def open_sink(ctx), do: open_stream(ctx)

  describe ":sqlite lifecycle" do
    @tag :stream_phase3
    test "open/2 requires a :path" do
      assert {:error, %Comn.Errors.ErrorStruct{code: "repo.stream/invalid_opts"}} =
               Stream.open(fresh_name(), backend: :sqlite)
    end

    @tag :stream_phase3
    test "open/2 twice under the same name returns already_exists", %{tmp_dir: dir} do
      name = fresh_name()
      path = Path.join(dir, "dup.db")
      {:ok, s} = Stream.open(name, backend: :sqlite, path: path)

      assert {:error, %Comn.Errors.ErrorStruct{code: "repo.stream/already_exists"}} =
               Stream.open(name, backend: :sqlite, path: path)

      Stream.drop(s)
    end

    @tag :stream_phase3
    test "open/2 creates parent directories", %{tmp_dir: dir} do
      path = Path.join([dir, "nested", "deeper", "s.db"])
      {:ok, s} = Stream.open(fresh_name(), backend: :sqlite, path: path)
      assert File.exists?(path)
      Stream.drop(s)
    end

    @tag :stream_phase3
    test "close/1 stops the stream and keeps the file", %{tmp_dir: dir} do
      path = Path.join(dir, "keep.db")
      {:ok, s} = Stream.open(fresh_name(), backend: :sqlite, path: path)
      assert :ok = Stream.close(s)
      assert {:error, %Comn.Errors.ErrorStruct{code: "repo.stream/not_found"}} = Stream.head(s)
      assert File.exists?(path)
      assert :ok = Stream.close(s)
    end

    @tag :stream_phase3
    test "drop/1 stops the stream and deletes the file", %{tmp_dir: dir} do
      path = Path.join(dir, "gone.db")
      {:ok, s} = Stream.open(fresh_name(), backend: :sqlite, path: path)
      assert :ok = Stream.drop(s)
      refute File.exists?(path)
      assert :ok = Stream.drop(s)
    end

    @tag :stream_phase3
    test "child_spec/1 starts a supervised stream", %{tmp_dir: dir} do
      name = fresh_name()
      spec = {Stream, name: name, backend: :sqlite, path: Path.join(dir, "sup.db")}
      {:ok, sup} = Supervisor.start_link([spec], strategy: :one_for_one)
      assert is_pid(Process.whereis(name))
      Supervisor.stop(sup)
      assert nil == Process.whereis(name)
    end
  end

  describe ":sqlite durability" do
    @tag :stream_phase3
    test "events and offsets survive close and reopen", %{tmp_dir: dir} do
      name = fresh_name()
      path = Path.join(dir, "durable.db")
      {:ok, s} = Stream.open(name, backend: :sqlite, path: path)

      {:ok, [o1, _, o3]} = Stream.append_many(s, Enum.map(1..3, &event(%{n: &1})))
      :ok = Stream.close(s)

      {:ok, s} = Stream.open(name, backend: :sqlite, path: path)
      assert {:ok, ^o3} = Stream.head(s)
      assert {:ok, ^o1} = Stream.tail(s)
      {:ok, events} = Stream.read(s, :head, 10)
      assert Enum.map(events, fn {_o, e} -> e.data.n end) == [1, 2, 3]

      # offsets keep climbing after reopen; nothing is reused
      {:ok, o4} = Stream.append(s, event(%{n: 4}))
      assert o4 > o3
      Stream.drop(s)
    end

    @tag :stream_phase3
    test "the same file can be reopened under a different name", %{tmp_dir: dir} do
      path = Path.join(dir, "rename.db")
      {:ok, a} = Stream.open(fresh_name(), backend: :sqlite, path: path)
      {:ok, o} = Stream.append(a, event(%{n: 1}))
      :ok = Stream.close(a)

      {:ok, b} = Stream.open(fresh_name(), backend: :sqlite, path: path)
      assert {:ok, ^o} = Stream.head(b)
      Stream.drop(b)
    end

    @tag :stream_phase3
    test "subscribers are delivered in append order from one serialised writer", %{tmp_dir: dir} do
      {:ok, s} = Stream.open(fresh_name(), backend: :sqlite, path: Path.join(dir, "order.db"))
      name = s.name
      {:ok, _} = Stream.subscribe(s)

      1..20
      |> Enum.map(fn n -> Task.async(fn -> Stream.append(s, event(%{n: n})) end) end)
      |> Enum.each(&Task.await/1)

      offsets =
        for _ <- 1..20 do
          receive do
            {:stream, ^name, o, _} -> o
          after
            500 -> flunk("missing live message")
          end
        end

      assert offsets == Enum.sort(offsets)
      Stream.drop(s)
    end
  end
end
