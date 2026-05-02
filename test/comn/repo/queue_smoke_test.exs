defmodule Comn.Repo.Queue.SmokeTest do
  @moduledoc false
  use ExUnit.Case, async: false
  @moduletag :tmp_dir

  alias Comn.Repo.Queue
  import Comn.Repo.QueueHelpers

  for backend <- [:mem, :sqlite] do
    @backend backend

    test "end-to-end #{backend} queue exercise", %{tmp_dir: dir} do
      open_opts =
        case @backend do
          :mem    -> []
          :sqlite -> [path: Path.join(dir, "smoke.queue")]
        end

      q = open_queue!(@backend, open_opts)

      # 1. push 10 items
      for i <- 1..10, do: :ok = Queue.push(q, %{n: i})
      assert Queue.size(q) == 10

      # 2. peek the first 3
      assert [%{n: 1}, %{n: 2}, %{n: 3}] = Queue.peek(q, 3)

      # 3. find an item past the head
      assert {:ok, %{n: 7}} = Queue.find(q, fn x -> x.n == 7 end)

      # 4. remove an item from the middle
      assert {:ok, %{n: 5}} = Queue.remove(q, fn x -> x.n == 5 end)
      assert Queue.size(q) == 9

      # 5. drain in FIFO order, skipping the removed item
      drained =
        Stream.unfold(:start, fn _ ->
          case Queue.pop(q, & &1) do
            :empty   -> nil
            {:ok, v} -> {v, :continue}
          end
        end)
        |> Enum.to_list()

      assert Enum.map(drained, & &1.n) == [1, 2, 3, 4, 6, 7, 8, 9, 10]
      assert Queue.size(q) == 0
    end
  end
end
