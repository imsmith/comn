defmodule Comn.RepoTest do
  use ExUnit.Case, async: true

  test "Comn.Repo behaviour defines required callbacks" do
    callbacks = Comn.Repo.behaviour_info(:callbacks)
    assert {:describe, 1} in callbacks
    assert {:get, 2} in callbacks
    assert {:set, 2} in callbacks
    assert {:delete, 2} in callbacks
    assert {:observe, 2} in callbacks
  end
end

defmodule Comn.Repo.Table.ETSTest do
  use ExUnit.Case

  alias Comn.Repo.Table.ETS
  alias Comn.Errors.ErrorStruct

  setup do
    table = :"test_table_#{:erlang.unique_integer([:positive])}"
    {:ok, _} = ETS.create(table)
    on_exit(fn ->
      try do
        ETS.drop(table)
      rescue
        ArgumentError -> :ok
      end
    end)
    %{table: table}
  end

  describe "create/1 and drop/1" do
    test "creates a new table" do
      name = :"create_test_#{:erlang.unique_integer([:positive])}"
      assert {:ok, _} = ETS.create(name)
      ETS.drop(name)
    end

    test "returns error when table already exists" do
      name = :"dup_test_#{:erlang.unique_integer([:positive])}"
      {:ok, _} = ETS.create(name)
      assert {:error, %ErrorStruct{code: "repo.table/already_exists"}} = ETS.create(name)
      ETS.drop(name)
    end

    test "drop returns error for nonexistent table" do
      assert {:error, %ErrorStruct{code: "repo.table/not_found"}} = ETS.drop(:nonexistent)
    end
  end

  describe "set/2 and get/2" do
    test "stores and retrieves a value", %{table: table} do
      assert :ok = ETS.set(table, key: "user:1", value: %{name: "Ian"})
      assert {:ok, %{name: "Ian"}} = ETS.get(table, key: "user:1")
    end

    test "overwrites existing key", %{table: table} do
      ETS.set(table, key: "k", value: "v1")
      ETS.set(table, key: "k", value: "v2")
      assert {:ok, "v2"} = ETS.get(table, key: "k")
    end

    test "get returns error for missing key", %{table: table} do
      assert {:error, %ErrorStruct{code: "repo.table/not_found"}} = ETS.get(table, key: "missing")
    end
  end

  describe "delete/2" do
    test "removes a key", %{table: table} do
      ETS.set(table, key: "del", value: "val")
      assert :ok = ETS.delete(table, key: "del")
      assert {:error, %ErrorStruct{code: "repo.table/not_found"}} = ETS.get(table, key: "del")
    end

    test "delete on missing key is silent", %{table: table} do
      assert :ok = ETS.delete(table, key: "nope")
    end
  end

  describe "describe/1" do
    test "returns table info", %{table: table} do
      assert {:ok, info} = ETS.describe(table)
      assert is_map(info)
      assert Map.has_key?(info, :size)
      assert Map.has_key?(info, :type)
    end

    test "returns error for nonexistent table" do
      assert {:error, %ErrorStruct{code: "repo.table/not_found"}} = ETS.describe(:nope)
    end
  end

  describe "keys/1" do
    test "returns all keys", %{table: table} do
      ETS.set(table, key: "a", value: 1)
      ETS.set(table, key: "b", value: 2)
      ETS.set(table, key: "c", value: 3)
      {:ok, keys} = ETS.keys(table)
      assert Enum.sort(keys) == ["a", "b", "c"]
    end

    test "returns empty list for empty table", %{table: table} do
      assert {:ok, []} = ETS.keys(table)
    end
  end

  describe "count/1" do
    test "returns number of entries", %{table: table} do
      assert {:ok, 0} = ETS.count(table)
      ETS.set(table, key: "x", value: 1)
      ETS.set(table, key: "y", value: 2)
      assert {:ok, 2} = ETS.count(table)
    end
  end

  describe "observe/2" do
    test "returns all entries as list", %{table: table} do
      ETS.set(table, key: "a", value: 1)
      ETS.set(table, key: "b", value: 2)
      entries = ETS.observe(table, [])
      assert is_list(entries)
      assert length(entries) == 2
      assert {"a", 1} in entries
      assert {"b", 2} in entries
    end
  end
end
