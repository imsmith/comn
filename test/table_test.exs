defmodule Comn.TableTest do
  @moduledoc """
  Acceptance test specifications for Comn.Repo.Table (the facade) and its
  :ets backend. The :ecto backend lives in test/table_ecto_test.exs.
  """

  use ExUnit.Case, async: true
  use Comn.TableConformance
  use Comn.EventSinkConformance, backend: Comn.Repo.Table

  doctest Comn.Repo.Table

  alias Comn.Repo.Table

  defp fresh_name, do: :"table_#{:erlang.unique_integer([:positive])}"

  def open_table(_ctx) do
    {:ok, t} = Table.open(fresh_name(), backend: :ets)
    {t, fn -> Table.drop(t) end}
  end

  def open_sink(ctx), do: open_table(ctx)

  describe "facade" do
    @tag :table_phase1
    test "look/recon/choices/act behave as a Comn facade" do
      assert is_binary(Table.look())
      assert %{type: :facade, extends: Comn.Repo, backends: backends} = Table.recon()
      assert :ets in backends
      assert is_map(Table.choices())

      assert {:error, %Comn.Errors.ErrorStruct{code: "comn/unknown_action"}} =
               Table.act(%{action: :bogus})
    end

    @tag :table_phase1
    test "open/2 with an unknown backend is invalid_opts" do
      assert {:error, %Comn.Errors.ErrorStruct{code: "repo.table/invalid_opts"}} =
               Table.open(fresh_name(), backend: :abacus)
    end

    @tag :table_phase1
    test "Comn.Repo.Table.ETS keeps its public surface" do
      name = fresh_name()
      {:ok, _} = Table.ETS.create(name)
      :ok = Table.ETS.set(name, key: :k, value: :v)
      assert {:ok, :v} = Table.ETS.get(name, key: :k)
      :ok = Table.ETS.drop(name)
    end
  end

  describe ":ets lifecycle" do
    @tag :table_phase1
    test "open/2 twice under the same name returns already_exists" do
      name = fresh_name()
      {:ok, t} = Table.open(name, backend: :ets)

      assert {:error, %Comn.Errors.ErrorStruct{code: "repo.table/already_exists"}} =
               Table.open(name, backend: :ets)

      Table.drop(t)
    end

    @tag :table_phase1
    test "drop/1 removes the table and is idempotent" do
      {:ok, t} = Table.open(fresh_name(), backend: :ets)
      assert :ok = Table.drop(t)
      assert {:error, %Comn.Errors.ErrorStruct{code: "repo.table/not_found"}} = Table.count(t)
      assert :ok = Table.drop(t)
    end

    @tag :table_phase1
    test "close/1 on :ets is drop (nothing is durable)" do
      {:ok, t} = Table.open(fresh_name(), backend: :ets)
      assert :ok = Table.close(t)
      assert {:error, _} = Table.count(t)
    end
  end
end
