defmodule Comn.Repo.Queue.MemTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias Comn.Repo.Queue
  import Comn.Repo.QueueHelpers

  describe "FIFO mem queue" do
    setup do
      {:ok, q: open_queue!(:mem, discipline: :fifo)}
    end

    test "push then pop returns items in insertion order", %{q: q} do
      :ok = Queue.push(q, :a)
      :ok = Queue.push(q, :b)
      :ok = Queue.push(q, :c)

      assert {:ok, :a} = Queue.pop(q, & &1)
      assert {:ok, :b} = Queue.pop(q, & &1)
      assert {:ok, :c} = Queue.pop(q, & &1)
      assert :empty    = Queue.pop(q, & &1)
    end

    test "size reflects pushed and acked items", %{q: q} do
      assert Queue.size(q) == 0
      :ok = Queue.push(q, :a)
      :ok = Queue.push(q, :b)
      assert Queue.size(q) == 2
      {:ok, :a} = Queue.pop(q, & &1)
      assert Queue.size(q) == 1
    end

    test "peek returns the head N without removing", %{q: q} do
      :ok = Queue.push(q, :a)
      :ok = Queue.push(q, :b)
      :ok = Queue.push(q, :c)
      assert Queue.peek(q, 2) == [:a, :b]
      assert Queue.size(q) == 3
    end

    test "find walks past the head", %{q: q} do
      :ok = Queue.push(q, %{n: 1})
      :ok = Queue.push(q, %{n: 2})
      :ok = Queue.push(q, %{n: 3})
      assert {:ok, %{n: 2}} = Queue.find(q, fn x -> x.n == 2 end)
      assert :not_found     = Queue.find(q, fn x -> x.n == 99 end)
    end

    test "remove extracts a non-head item", %{q: q} do
      :ok = Queue.push(q, %{n: 1})
      :ok = Queue.push(q, %{n: 2})
      :ok = Queue.push(q, %{n: 3})
      assert {:ok, %{n: 2}} = Queue.remove(q, fn x -> x.n == 2 end)
      assert Queue.size(q) == 2
      assert {:ok, %{n: 1}} = Queue.pop(q, & &1)
      assert {:ok, %{n: 3}} = Queue.pop(q, & &1)
    end
  end

  describe "LIFO mem queue" do
    setup do
      {:ok, q: open_queue!(:mem, discipline: :lifo)}
    end

    test "pop returns the most-recently pushed item", %{q: q} do
      :ok = Queue.push(q, :a)
      :ok = Queue.push(q, :b)
      :ok = Queue.push(q, :c)
      assert {:ok, :c} = Queue.pop(q, & &1)
      assert {:ok, :b} = Queue.pop(q, & &1)
      assert {:ok, :a} = Queue.pop(q, & &1)
    end
  end

  describe "crash safety" do
    setup do
      {:ok, q: open_queue!(:mem)}
    end

    test "if the callback raises, the item is requeued and the exception re-raised", %{q: q} do
      :ok = Queue.push(q, :flaky)

      assert_raise RuntimeError, "boom", fn ->
        Queue.pop(q, fn :flaky -> raise "boom" end)
      end

      assert Queue.size(q) == 1
      assert {:ok, :handled} = Queue.pop(q, fn :flaky -> :handled end)
    end

    test "if the callback throws, the item is requeued", %{q: q} do
      :ok = Queue.push(q, :item)

      catch_throw(Queue.pop(q, fn _ -> throw(:nope) end))

      assert Queue.size(q) == 1
    end

    test "if the callback exits, the item is requeued", %{q: q} do
      :ok = Queue.push(q, :item)

      catch_exit(Queue.pop(q, fn _ -> exit(:wat) end))

      assert Queue.size(q) == 1
    end

    test "concurrent reservations never deliver the same item twice", %{q: q} do
      for n <- 1..50, do: :ok = Queue.push(q, n)

      results =
        1..10
        |> Enum.map(fn _ ->
          Task.async(fn ->
            drain(q, [])
          end)
        end)
        |> Task.await_many(5_000)
        |> List.flatten()
        |> Enum.sort()

      assert results == Enum.to_list(1..50)
    end

    defp drain(q, acc) do
      case Queue.pop(q, & &1) do
        :empty   -> Enum.reverse(acc)
        {:ok, v} -> drain(q, [v | acc])
      end
    end
  end
end
