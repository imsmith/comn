defmodule Comn.EtsLifecycleTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias Comn.Repo.Table.ETS
  alias Comn.Errors.ErrorStruct

  describe "table ownership" do
    test "table survives across calls (no process ownership issue)" do
      name = :"lifecycle_#{:erlang.unique_integer([:positive])}"
      {:ok, _} = ETS.create(name)

      # Write from this process
      :ok = ETS.set(name, key: "a", value: 1)

      # Read from a spawned task
      result =
        Task.async(fn ->
          ETS.get(name, key: "a")
        end)
        |> Task.await()

      assert {:ok, 1} = result
      ETS.drop(name)
    end

    test "operations on dropped table return not_found" do
      name = :"dropped_#{:erlang.unique_integer([:positive])}"
      {:ok, _} = ETS.create(name)
      :ok = ETS.drop(name)

      assert {:error, %ErrorStruct{code: "repo.table/not_found"}} = ETS.get(name, key: "x")
      assert {:error, %ErrorStruct{code: "repo.table/not_found"}} = ETS.set(name, key: "x", value: 1)
      assert {:error, %ErrorStruct{code: "repo.table/not_found"}} = ETS.delete(name, key: "x")
      assert {:error, %ErrorStruct{code: "repo.table/not_found"}} = ETS.keys(name)
      assert {:error, %ErrorStruct{code: "repo.table/not_found"}} = ETS.count(name)
      assert {:error, %ErrorStruct{code: "repo.table/not_found"}} = ETS.describe(name)
    end

    test "concurrent writes don't lose data" do
      name = :"concurrent_#{:erlang.unique_integer([:positive])}"
      {:ok, _} = ETS.create(name)

      tasks =
        for i <- 1..100 do
          Task.async(fn ->
            ETS.set(name, key: "key_#{i}", value: i)
          end)
        end

      Enum.each(tasks, &Task.await/1)

      {:ok, count} = ETS.count(name)
      assert count == 100

      ETS.drop(name)
    end
  end

  describe "create edge cases" do
    test "double create returns already_exists" do
      name = :"double_#{:erlang.unique_integer([:positive])}"
      {:ok, _} = ETS.create(name)
      assert {:error, %ErrorStruct{code: "repo.table/already_exists"}} = ETS.create(name)
      ETS.drop(name)
    end

    test "create after drop succeeds" do
      name = :"recreate_#{:erlang.unique_integer([:positive])}"
      {:ok, _} = ETS.create(name)
      :ok = ETS.drop(name)
      {:ok, _} = ETS.create(name)
      ETS.drop(name)
    end
  end
end
