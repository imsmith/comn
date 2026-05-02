defmodule Comn.Repo.Queue.PropertyTest do
  @moduledoc false
  use ExUnit.Case, async: false
  use ExUnitProperties

  @moduletag :tmp_dir

  alias Comn.Repo.Queue
  import Comn.Repo.QueueHelpers

  describe "FIFO ordering" do
    property "pop returns items in push order (Mem)", %{tmp_dir: _dir} do
      check all items <- list_of(integer(), min_length: 1, max_length: 200) do
        q = open_queue!(:mem, discipline: :fifo)
        for v <- items, do: :ok = Queue.push(q, v)

        popped = drain(q, [])
        assert popped == items
      end
    end

    property "pop returns items in push order (SQLite)", %{tmp_dir: dir} do
      check all items <- list_of(integer(), min_length: 1, max_length: 100), max_runs: 25 do
        path = Path.join(dir, "fifo_#{System.unique_integer([:positive])}.queue")
        q = open_queue!(:sqlite, path: path, discipline: :fifo)
        for v <- items, do: :ok = Queue.push(q, v)
        popped = drain(q, [])
        assert popped == items
      end
    end
  end

  describe "LIFO ordering" do
    property "pop returns items in reverse push order (Mem)" do
      check all items <- list_of(integer(), min_length: 1, max_length: 200) do
        q = open_queue!(:mem, discipline: :lifo)
        for v <- items, do: :ok = Queue.push(q, v)
        popped = drain(q, [])
        assert popped == Enum.reverse(items)
      end
    end
  end

  describe "crash safety preserves all items" do
    property "raising in 50% of pop callbacks loses no items (Mem)" do
      check all items <- list_of(integer(1..1_000_000), min_length: 1, max_length: 50),
                seed  <- integer() do
        :rand.seed(:exsplus, {seed, seed, seed})
        q = open_queue!(:mem)
        for v <- items, do: :ok = Queue.push(q, v)

        popped = drain_with_flakiness(q, [], 0.5)
        assert Enum.sort(popped) == Enum.sort(items)
      end
    end
  end

  describe "concurrency never double-delivers" do
    property "N workers draining one queue produce a partition (Mem)" do
      check all items   <- list_of(integer(1..1_000_000), min_length: 10, max_length: 200),
                workers <- integer(1..16) do
        q = open_queue!(:mem)
        for v <- items, do: :ok = Queue.push(q, v)

        results =
          1..workers
          |> Enum.map(fn _ -> Task.async(fn -> drain(q, []) end) end)
          |> Task.await_many(10_000)
          |> List.flatten()
          |> Enum.sort()

        assert results == Enum.sort(items)
      end
    end
  end

  defp drain(q, acc) do
    case Queue.pop(q, & &1) do
      :empty   -> Enum.reverse(acc)
      {:ok, v} -> drain(q, [v | acc])
    end
  end

  defp drain_with_flakiness(q, acc, p) do
    case Queue.pop(q, fn v ->
           if :rand.uniform() < p, do: raise("flake"), else: v
         end) do
      :empty                       -> Enum.reverse(acc)
      {:ok, v}                     -> drain_with_flakiness(q, [v | acc], p)
    end
  rescue
    RuntimeError -> drain_with_flakiness(q, acc, p)
  end
end
