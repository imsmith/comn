defmodule Comn.Repo.Queue.SQLiteTest do
  @moduledoc false
  use ExUnit.Case, async: false
  @moduletag :tmp_dir

  alias Comn.Repo.Queue
  import Comn.Repo.QueueHelpers

  describe "FIFO sqlite queue" do
    test "push then pop returns items in insertion order across re-opens", %{tmp_dir: dir} do
      path = Path.join(dir, "q.queue")

      q = open_queue!(:sqlite, path: path, discipline: :fifo)
      :ok = Queue.push(q, :a)
      :ok = Queue.push(q, :b)
      :ok = Queue.push(q, :c)
      :ok = Queue.close(q)

      q2 = open_queue!(:sqlite, path: path, discipline: :fifo)
      assert {:ok, :a} = Queue.pop(q2, & &1)
      assert {:ok, :b} = Queue.pop(q2, & &1)
      assert {:ok, :c} = Queue.pop(q2, & &1)
      assert :empty    = Queue.pop(q2, & &1)
    end

    test "items survive close/open with reservation reaping", %{tmp_dir: dir} do
      path = Path.join(dir, "q.queue")

      q = open_queue!(:sqlite, path: path, discipline: :fifo)
      :ok = Queue.push(q, :keep_me)

      # Simulate a crash between reserve and ack: forcefully terminate the
      # backend GenServer while a reservation is held. Easiest path is to
      # call reserve directly via the backend.
      %Comn.Repo.Queue.Handle{state: pid} = q
      assert {:ok, {_token, :keep_me}} = Comn.Repo.Queue.SQLite.reserve(pid)
      Process.unlink(pid)
      Process.exit(pid, :kill)
      Process.sleep(50)

      # Re-open: stale reservation should be cleared and item available again.
      q2 = open_queue!(:sqlite, path: path, discipline: :fifo)
      assert {:ok, :keep_me} = Queue.pop(q2, & &1)
    end
  end

  describe "LIFO sqlite queue" do
    test "pop returns most recently pushed", %{tmp_dir: dir} do
      path = Path.join(dir, "lq.queue")
      q = open_queue!(:sqlite, path: path, discipline: :lifo)

      for v <- [:a, :b, :c], do: :ok = Queue.push(q, v)

      assert {:ok, :c} = Queue.pop(q, & &1)
      assert {:ok, :b} = Queue.pop(q, & &1)
      assert {:ok, :a} = Queue.pop(q, & &1)
    end
  end

  describe "complex item types" do
    test "round-trips maps, lists, tuples, atoms via term_to_binary", %{tmp_dir: dir} do
      path = Path.join(dir, "complex.queue")
      q = open_queue!(:sqlite, path: path)

      payload = %{
        path: "/abs/path/to/doc.pdf",
        attempt: 3,
        meta: {:figures, [:full, :captions]},
        binary: <<0, 1, 2, 255>>
      }

      :ok = Queue.push(q, payload)
      assert {:ok, ^payload} = Queue.pop(q, & &1)
    end
  end

  describe "rejects bad open opts" do
    test "missing :path returns invalid_opts" do
      assert {:error, %{code: "repo.queue/invalid_opts"}} =
               Queue.open(:bad, backend: :sqlite)
    end
  end
end
