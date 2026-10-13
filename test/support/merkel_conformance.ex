defmodule Comn.MerkelConformance do
  @moduledoc """
  Shared acceptance spec for `Comn.Repo.Merkel` backends, run entirely
  through the public facade.

  A backend test module does:

      use Comn.MerkelConformance

      def open_merkel(_ctx) do
        {:ok, m} = Comn.Repo.Merkel.open(:"m_\#{System.unique_integer([:positive])}", backend: :mem)
        {m, fn -> Comn.Repo.Merkel.drop(m) end}
      end

  Each backend module adds `tamper/2`, which corrupts the stored content
  behind an address in whatever way that medium can be corrupted; the spec
  asserts `verify/1` catches it. Any `@moduletag` the backend needs must
  precede the `use` line.

  Phase tag: `:merkel_phase1`.
  """

  defmacro __using__(_opts) do
    quote location: :keep do
      alias Comn.Events.EventStruct
      alias Comn.Repo.Merkel

      defp entry(payload \\ %{}, topic \\ "merkel.test") do
        EventStruct.new(:test, topic, payload)
      end

      defp open!(ctx) do
        {m, cleanup} = open_merkel(ctx)
        on_exit(cleanup)
        m
      end

      describe "put and get (#{__MODULE__})" do
        setup ctx, do: %{m: open!(ctx)}

        @tag :merkel_phase1
        test "put/2 returns a content address and get/2 returns the content", %{m: m} do
          e = entry(%{n: 1})
          {:ok, a} = Merkel.put(m, e)
          assert is_binary(a)
          assert {:ok, ^e} = Merkel.get(m, a)
        end

        @tag :merkel_phase1
        test "the same content put twice gets two addresses: each put extends the chain", %{m: m} do
          e = entry(%{n: 1})
          {:ok, a1} = Merkel.put(m, e)
          {:ok, a2} = Merkel.put(m, e)
          assert a1 != a2
          assert {:ok, ^e} = Merkel.get(m, a1)
          assert {:ok, ^e} = Merkel.get(m, a2)
        end

        @tag :merkel_phase1
        test "get/2 of an unknown address is unknown_address", %{m: m} do
          assert {:error, %Comn.Errors.ErrorStruct{code: "repo.merkel/unknown_address"}} =
                   Merkel.get(m, "0000000000000000000000000000000000000000")
        end

        @tag :merkel_phase1
        test "put/2 accepts anything Comn.Event converts and stores an EventStruct", %{m: m} do
          {:ok, a} = Merkel.put(m, %{type: :domain, topic: "merkel.map", data: %{n: 1}})
          assert {:ok, %EventStruct{topic: "merkel.map"}} = Merkel.get(m, a)
        end

        @tag :merkel_phase1
        test "put/2 rejects what Comn.Event cannot convert", %{m: m} do
          assert {:error, %Comn.Errors.ErrorStruct{code: "repo.merkel/invalid_event"}} =
                   Merkel.put(m, %{not: "an event"})
        end
      end

      describe "head and chain (#{__MODULE__})" do
        setup ctx, do: %{m: open!(ctx)}

        @tag :merkel_phase1
        test "head/1 is nil on an empty merkel", %{m: m} do
          assert {:ok, nil} = Merkel.head(m)
        end

        @tag :merkel_phase1
        test "head/1 is the address of the latest put", %{m: m} do
          {:ok, a1} = Merkel.put(m, entry(%{n: 1}))
          assert {:ok, ^a1} = Merkel.head(m)
          {:ok, a2} = Merkel.put(m, entry(%{n: 2}))
          assert {:ok, ^a2} = Merkel.head(m)
        end

        @tag :merkel_phase1
        test "each node links to its parent; genesis has none", %{m: m} do
          {:ok, a1} = Merkel.put(m, entry(%{n: 1}))
          {:ok, a2} = Merkel.put(m, entry(%{n: 2}))
          assert {:ok, %Merkel.Node{address: ^a2, parent: ^a1}} = Merkel.node(m, a2)
          assert {:ok, %Merkel.Node{address: ^a1, parent: nil}} = Merkel.node(m, a1)
        end

        @tag :merkel_phase1
        test "observe/2 as events walks root to genesis, newest first", %{m: m} do
          events = for n <- 1..3, do: entry(%{n: n})
          Enum.each(events, &({:ok, _} = Merkel.put(m, &1)))
          assert Merkel.observe(m, as: :events) |> Enum.to_list() == Enum.reverse(events)
        end

        @tag :merkel_phase1
        test "describe/1 reports root and length", %{m: m} do
          assert {:ok, %{root: nil, length: 0}} = Merkel.describe(m)
          {:ok, a} = Merkel.put(m, entry())
          assert {:ok, %{root: ^a, length: 1, backend: _, name: _}} = Merkel.describe(m)
        end

        @tag :merkel_phase1
        test "delete/2 is immutable", %{m: m} do
          {:ok, a} = Merkel.put(m, entry())

          assert {:error, %Comn.Errors.ErrorStruct{code: "repo.merkel/immutable"}} =
                   Merkel.delete(m, address: a)
        end
      end

      describe "verify (#{__MODULE__})" do
        setup ctx, do: %{m: open!(ctx)}

        @tag :merkel_phase1
        test "verify/1 is ok on an empty and on an intact chain", %{m: m} do
          assert :ok = Merkel.verify(m)
          Enum.each(1..3, &({:ok, _} = Merkel.put(m, entry(%{n: &1}))))
          assert :ok = Merkel.verify(m)
        end

        @tag :merkel_phase1
        test "verify/1 names the first tampered address", %{m: m} do
          {:ok, a1} = Merkel.put(m, entry(%{n: 1}))
          {:ok, _a2} = Merkel.put(m, entry(%{n: 2}))
          :ok = tamper(m, a1)

          assert {:error, %Comn.Errors.ErrorStruct{code: "repo.merkel/tampered", field: ^a1}} =
                   Merkel.verify(m)
        end
      end
    end
  end
end
