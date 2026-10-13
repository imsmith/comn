defmodule Comn.TableConformance do
  @moduledoc """
  Shared acceptance spec for `Comn.Repo.Table` backends, run entirely
  through the public facade.

  A backend test module does:

      use Comn.TableConformance

      def open_table(_ctx) do
        {:ok, t} = Comn.Repo.Table.open(:"t_\#{System.unique_integer([:positive])}", backend: :ets)
        {t, fn -> Comn.Repo.Table.drop(t) end}
      end

  Any `@moduletag` the backend needs must precede the `use` line.
  Phase tag: `:table_phase1`.
  """

  defmacro __using__(_opts) do
    quote location: :keep do
      alias Comn.Repo.Table

      defp open!(ctx) do
        {t, cleanup} = open_table(ctx)
        on_exit(cleanup)
        t
      end

      describe "key-value verbs (#{__MODULE__})" do
        setup ctx, do: %{t: open!(ctx)}

        @tag :table_phase1
        test "set/3 then get/2 round-trips any term", %{t: t} do
          :ok = Table.set(t, "user:1", %{name: "Ian", tags: [:a, {:b, 2}]})
          assert {:ok, %{name: "Ian", tags: [:a, {:b, 2}]}} = Table.get(t, "user:1")
        end

        @tag :table_phase1
        test "set/3 overwrites", %{t: t} do
          :ok = Table.set(t, :k, 1)
          :ok = Table.set(t, :k, 2)
          assert {:ok, 2} = Table.get(t, :k)
          assert {:ok, 1} = Table.count(t)
        end

        @tag :table_phase1
        test "get/2 of a missing key is repo.table/not_found", %{t: t} do
          assert {:error, %Comn.Errors.ErrorStruct{code: "repo.table/not_found"}} =
                   Table.get(t, :nope)
        end

        @tag :table_phase1
        test "delete/2 removes a key and is idempotent", %{t: t} do
          :ok = Table.set(t, :k, 1)
          assert :ok = Table.delete(t, :k)
          assert {:error, _} = Table.get(t, :k)
          assert :ok = Table.delete(t, :k)
        end

        @tag :table_phase1
        test "keys/1 and count/1 reflect the contents", %{t: t} do
          assert {:ok, []} = Table.keys(t)
          assert {:ok, 0} = Table.count(t)
          for k <- [:a, :b, :c], do: :ok = Table.set(t, k, 0)
          {:ok, keys} = Table.keys(t)
          assert Enum.sort(keys) == [:a, :b, :c]
          assert {:ok, 3} = Table.count(t)
        end

        @tag :table_phase1
        test "describe/1 names the table and backend", %{t: t} do
          assert {:ok, %{name: name, backend: b}} = Table.describe(t)
          assert name == t.name and is_atom(b)
        end

        @tag :table_phase1
        test "observe/2 lists {key, value} pairs", %{t: t} do
          :ok = Table.set(t, :a, 1)
          :ok = Table.set(t, :b, 2)
          assert Table.observe(t) |> Enum.sort() == [a: 1, b: 2]
        end

        @tag :table_phase1
        test "Repo keyword forms still work: set key:/value:, get key:, delete key:", %{t: t} do
          assert :ok = Table.set(t, key: :k, value: :v)
          assert {:ok, :v} = Table.get(t, key: :k)
          assert :ok = Table.delete(t, key: :k)
        end
      end
    end
  end
end
