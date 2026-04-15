defmodule Comn.Repo.Batch.MemTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias Comn.Repo.Batch.Mem, as: Batch
  alias Comn.Errors.ErrorStruct

  setup do
    id = :erlang.unique_integer([:positive])
    flushed_name = :"flushed_#{id}"
    flushed = :ets.new(flushed_name, [:named_table, :public, :set])
    :ets.insert(flushed, {:batches, []})

    on_flush = fn items ->
      [{:batches, existing}] = :ets.lookup(flushed_name, :batches)
      :ets.insert(flushed_name, {:batches, existing ++ [items]})
      :ok
    end

    name = :"batch_#{id}"

    {:ok, pid} = Batch.start_link(
      name: name,
      max_size: 5,
      interval_ms: 0,
      on_flush: on_flush
    )

    on_exit(fn ->
      if Process.alive?(pid), do: GenServer.stop(pid)
      try do
        :ets.delete(flushed_name)
      rescue
        ArgumentError -> :ok
      end
    end)

    %{name: name, flushed: flushed_name}
  end

  defp flushed_batches(flushed_name) do
    [{:batches, batches}] = :ets.lookup(flushed_name, :batches)
    batches
  end

  describe "add/2 and pending/1" do
    test "buffers items", %{name: name} do
      :ok = Batch.add(name, :a)
      :ok = Batch.add(name, :b)
      :ok = Batch.add(name, :c)
      {:ok, 3} = Batch.pending(name)
    end
  end

  describe "add_many/2" do
    test "buffers multiple items at once", %{name: name} do
      :ok = Batch.add_many(name, [:a, :b, :c])
      {:ok, 3} = Batch.pending(name)
    end
  end

  describe "flush/1" do
    test "flushes buffer and calls on_flush", %{name: name, flushed: flushed} do
      Batch.add_many(name, [1, 2, 3])
      {:ok, 3} = Batch.flush(name)
      {:ok, 0} = Batch.pending(name)

      assert flushed_batches(flushed) == [[1, 2, 3]]
    end

    test "flushing empty buffer returns 0", %{name: name} do
      {:ok, 0} = Batch.flush(name)
    end

    test "multiple flushes accumulate", %{name: name, flushed: flushed} do
      Batch.add_many(name, [:a, :b])
      {:ok, 2} = Batch.flush(name)

      Batch.add_many(name, [:c, :d])
      {:ok, 2} = Batch.flush(name)

      assert flushed_batches(flushed) == [[:a, :b], [:c, :d]]
    end
  end

  describe "auto-flush on max_size" do
    test "triggers flush when buffer hits threshold", %{name: name, flushed: flushed} do
      Batch.add_many(name, [1, 2, 3, 4, 5])
      {:ok, 0} = Batch.pending(name)

      assert flushed_batches(flushed) == [[1, 2, 3, 4, 5]]
    end
  end

  describe "config/1" do
    test "returns configuration", %{name: name} do
      {:ok, config} = Batch.config(name)
      assert config.max_size == 5
      assert config.interval_ms == 0
    end

    test "tracks total_flushed", %{name: name} do
      Batch.add_many(name, [1, 2])
      Batch.flush(name)
      Batch.add_many(name, [3, 4, 5])
      Batch.flush(name)

      {:ok, config} = Batch.config(name)
      assert config.total_flushed == 5
    end
  end

  describe "interval-based auto-flush" do
    test "flushes on timer tick" do
      flushed = :ets.new(:interval_flushed, [:public, :set])
      :ets.insert(flushed, {:batches, []})

      on_flush = fn items ->
        [{:batches, existing}] = :ets.lookup(flushed, :batches)
        :ets.insert(flushed, {:batches, existing ++ [items]})
        :ok
      end

      name = :"interval_batch_#{:erlang.unique_integer([:positive])}"

      {:ok, pid} = Batch.start_link(
        name: name,
        max_size: 1000,
        interval_ms: 50,
        on_flush: on_flush
      )

      Batch.add_many(name, [:x, :y, :z])

      # Wait for the timer to fire
      Process.sleep(100)

      {:ok, 0} = Batch.pending(name)

      [{:batches, batches}] = :ets.lookup(flushed, :batches)
      assert batches == [[:x, :y, :z]]

      GenServer.stop(pid)
      :ets.delete(flushed)
    end
  end

  describe "Comn.Repo callbacks" do
    test "describe/1 returns metadata", %{name: name} do
      Batch.add(name, :item)
      {:ok, info} = Batch.describe(name)
      assert info.pending == 1
      assert info.max_size == 5
    end

    test "get/2 returns error (write-only)", %{name: name} do
      assert {:error, %ErrorStruct{}} = Batch.get(name, key: "x")
    end

    test "set/2 delegates to add", %{name: name} do
      :ok = Batch.set(name, value: :item)
      {:ok, 1} = Batch.pending(name)
    end

    test "delete/2 returns error (not supported)", %{name: name} do
      assert {:error, %ErrorStruct{}} = Batch.delete(name, key: "x")
    end

    test "observe/2 returns current buffer", %{name: name} do
      Batch.add_many(name, [1, 2, 3])
      items = Batch.observe(name, [])
      assert items == [1, 2, 3]
    end
  end

  describe "on_flush failure" do
    test "flush returns error if callback fails" do
      name = :"fail_batch_#{:erlang.unique_integer([:positive])}"

      {:ok, pid} = Batch.start_link(
        name: name,
        max_size: 1000,
        interval_ms: 0,
        on_flush: fn _items -> {:error, :backend_down} end
      )

      Batch.add(name, :item)
      assert {:error, :backend_down} = Batch.flush(name)

      # Buffer is preserved on failure
      {:ok, 1} = Batch.pending(name)

      GenServer.stop(pid)
    end
  end

  describe "Comn behaviour" do
    test "look/0" do
      assert Batch.look() == "Batch.Mem — in-memory GenServer batch buffer with auto-flush"
    end

    test "recon/0" do
      assert %{backend: :memory, type: :implementation} = Batch.recon()
    end

    test "discovery finds Batch modules" do
      impls = Comn.Discovery.implementations_of(Comn.Repo.Batch)
      assert Comn.Repo.Batch.Mem in impls
    end
  end
end
