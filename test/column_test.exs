defmodule Comn.Repo.Column.ETSTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias Comn.Repo.Column.ETS, as: Col
  alias Comn.Errors.ErrorStruct

  @schema %{ts: :datetime, host: :string, cpu: :float, mem: :float}

  setup do
    name = :"col_test_#{:erlang.unique_integer([:positive])}"
    {:ok, store} = Col.create(name)
    :ok = Col.define_schema(store, @schema)

    on_exit(fn ->
      try do
        Col.drop(name)
      rescue
        ArgumentError -> :ok
      end
    end)

    %{store: store, name: name}
  end

  describe "create/1 and drop/1" do
    test "creates a new column store", %{store: store} do
      assert %Col{} = store
    end

    test "drop cleans up tables", %{name: name} do
      :ok = Col.drop(name)
      assert {:error, %ErrorStruct{code: "repo.column/not_found"}} = Col.drop(name)
    end
  end

  describe "define_schema/2" do
    test "sets the schema", %{store: store} do
      {:ok, schema} = Col.schema(store)
      assert schema == @schema
    end

    test "rejects non-atom keys" do
      name = :"bad_schema_#{:erlang.unique_integer([:positive])}"
      {:ok, store} = Col.create(name)
      assert {:error, %ErrorStruct{code: "repo.column/invalid_schema"}} =
               Col.define_schema(store, %{"bad" => :string})
      Col.drop(name)
    end
  end

  describe "append_row/2" do
    test "appends a conforming row", %{store: store} do
      row = %{ts: "2024-01-01T00:00:00Z", host: "web-1", cpu: 0.42, mem: 0.65}
      assert :ok = Col.append_row(store, row)
    end

    test "rejects row with wrong columns", %{store: store} do
      assert {:error, %ErrorStruct{code: "repo.column/schema_mismatch"}} =
               Col.append_row(store, %{ts: "now", host: "web-1"})
    end

    test "rejects row with extra columns", %{store: store} do
      assert {:error, %ErrorStruct{code: "repo.column/schema_mismatch"}} =
               Col.append_row(store, %{ts: "now", host: "web-1", cpu: 0.1, mem: 0.2, extra: true})
    end
  end

  describe "append_rows/2" do
    test "appends multiple rows", %{store: store} do
      rows = [
        %{ts: "2024-01-01T00:00:00Z", host: "web-1", cpu: 0.42, mem: 0.65},
        %{ts: "2024-01-01T00:01:00Z", host: "web-2", cpu: 0.38, mem: 0.71}
      ]

      assert :ok = Col.append_rows(store, rows)
      {:ok, 2} = Col.count(store, %{})
    end

    test "stops on first bad row", %{store: store} do
      rows = [
        %{ts: "2024-01-01T00:00:00Z", host: "web-1", cpu: 0.42, mem: 0.65},
        %{bad: "row"},
        %{ts: "2024-01-01T00:02:00Z", host: "web-3", cpu: 0.5, mem: 0.8}
      ]

      assert {:error, %ErrorStruct{code: "repo.column/schema_mismatch"}} =
               Col.append_rows(store, rows)

      # Only the first row made it
      {:ok, 1} = Col.count(store, %{})
    end
  end

  describe "project/3" do
    setup %{store: store} do
      rows = [
        %{ts: "2024-01-01T00:00:00Z", host: "web-1", cpu: 0.42, mem: 0.65},
        %{ts: "2024-01-01T00:01:00Z", host: "web-2", cpu: 0.38, mem: 0.71},
        %{ts: "2024-01-01T00:02:00Z", host: "web-1", cpu: 0.55, mem: 0.60}
      ]

      Col.append_rows(store, rows)
      :ok
    end

    test "selects specific columns", %{store: store} do
      {:ok, rows} = Col.project(store, [:host, :cpu], %{})
      assert length(rows) == 3
      assert Map.keys(hd(rows)) |> Enum.sort() == [:cpu, :host]
    end

    test "empty fields returns all columns", %{store: store} do
      {:ok, rows} = Col.project(store, [], %{})
      assert length(rows) == 3
      assert Map.keys(hd(rows)) |> Enum.sort() == [:cpu, :host, :mem, :ts]
    end

    test "filters by column value", %{store: store} do
      {:ok, rows} = Col.project(store, [:ts, :cpu], %{host: "web-1"})
      assert length(rows) == 2
      assert Enum.all?(rows, &(not Map.has_key?(&1, :host)))
    end

    test "rejects unknown columns", %{store: store} do
      assert {:error, %ErrorStruct{code: "repo.column/unknown_column"}} =
               Col.project(store, [:host, :bogus], %{})
    end
  end

  describe "count/2" do
    test "returns total count", %{store: store} do
      Col.append_row(store, %{ts: "now", host: "a", cpu: 0.1, mem: 0.2})
      Col.append_row(store, %{ts: "now", host: "b", cpu: 0.3, mem: 0.4})
      {:ok, 2} = Col.count(store, %{})
    end

    test "returns filtered count", %{store: store} do
      Col.append_row(store, %{ts: "now", host: "a", cpu: 0.1, mem: 0.2})
      Col.append_row(store, %{ts: "now", host: "b", cpu: 0.3, mem: 0.4})
      Col.append_row(store, %{ts: "now", host: "a", cpu: 0.5, mem: 0.6})
      {:ok, 2} = Col.count(store, %{host: "a"})
    end
  end

  describe "flush/1" do
    test "returns row count (ETS writes are immediate)", %{store: store} do
      Col.append_row(store, %{ts: "now", host: "a", cpu: 0.1, mem: 0.2})
      Col.append_row(store, %{ts: "now", host: "b", cpu: 0.3, mem: 0.4})
      {:ok, 2} = Col.flush(store)
    end
  end

  describe "Comn.Repo callbacks" do
    test "describe/1 returns store metadata", %{store: store} do
      Col.append_row(store, %{ts: "now", host: "a", cpu: 0.1, mem: 0.2})
      {:ok, info} = Col.describe(store)
      assert info.schema == @schema
      assert info.row_count == 1
    end

    test "get/2 returns error (not supported)", %{store: store} do
      assert {:error, %ErrorStruct{code: "repo.column/query_failed"}} =
               Col.get(store, key: "x")
    end

    test "set/2 delegates to append_row", %{store: store} do
      row = %{ts: "now", host: "a", cpu: 0.1, mem: 0.2}
      assert :ok = Col.set(store, value: row)
      {:ok, 1} = Col.count(store, %{})
    end

    test "delete/2 returns error (not supported)", %{store: store} do
      assert {:error, %ErrorStruct{code: "repo.column/query_failed"}} =
               Col.delete(store, key: "x")
    end
  end

  describe "Comn behaviour" do
    test "look/0" do
      assert Col.look() == "Column.ETS — in-memory column store backed by ETS"
    end

    test "recon/0" do
      assert %{backend: :ets, type: :implementation} = Col.recon()
    end

    test "discovery finds Column modules" do
      impls = Comn.Discovery.implementations_of(Comn.Repo.Column)
      assert Comn.Repo.Column.ETS in impls
    end
  end
end
