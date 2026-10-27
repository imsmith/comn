defmodule Comn.StreamConformance.Log do
  @moduledoc """
  The log half of `Comn.StreamConformance`: append, read, head, and tail.
  Phase tag `:stream_phase1`. Use it through `Comn.StreamConformance`,
  which supplies `event/2` and `open!/1`.
  """

  defmacro __using__(_opts) do
    quote location: :keep do
      alias Comn.Events.EventStruct
      alias Comn.Repo.Stream

      describe "append (#{__MODULE__})" do
        setup ctx, do: %{s: open!(ctx)}

        @tag :stream_phase1
        test "append/2 returns monotonically increasing offsets", %{s: s} do
          {:ok, o1} = Stream.append(s, event(%{n: 1}))
          {:ok, o2} = Stream.append(s, event(%{n: 2}))
          {:ok, o3} = Stream.append(s, event(%{n: 3}))
          assert o1 < o2 and o2 < o3
        end

        @tag :stream_phase1
        test "append/2 on a non-EventStruct returns invalid_event", %{s: s} do
          assert {:error, %Comn.Errors.ErrorStruct{code: "repo.stream/invalid_event"}} =
                   Stream.append(s, %{not: "an event"})
        end

        @tag :stream_phase1
        test "append_many/2 returns offsets in input order", %{s: s} do
          events = for n <- 1..5, do: event(%{n: n})
          {:ok, offsets} = Stream.append_many(s, events)
          assert length(offsets) == 5
          assert offsets == Enum.sort(offsets)
        end

        @tag :stream_phase1
        test "append_many/2 with one bad event appends nothing", %{s: s} do
          assert {:error, %Comn.Errors.ErrorStruct{code: "repo.stream/invalid_event"}} =
                   Stream.append_many(s, [event(), :bad])

          assert {:ok, nil} = Stream.head(s)
        end
      end

      describe "read (#{__MODULE__})" do
        setup ctx do
          s = open!(ctx)
          {:ok, offsets} = Stream.append_many(s, for(n <- 1..5, do: event(%{n: n})))
          %{s: s, offsets: offsets}
        end

        @tag :stream_phase1
        test "read from :head returns the first N events", %{s: s} do
          {:ok, results} = Stream.read(s, :head, 3)
          assert Enum.map(results, fn {_o, e} -> e.data.n end) == [1, 2, 3]
        end

        @tag :stream_phase1
        test "read from :tail returns the last N events", %{s: s} do
          {:ok, results} = Stream.read(s, :tail, 2)
          assert Enum.map(results, fn {_o, e} -> e.data.n end) == [4, 5]
        end

        @tag :stream_phase1
        test "read from an explicit offset returns events at and after it", %{
          s: s,
          offsets: [_, _, o3 | _]
        } do
          {:ok, results} = Stream.read(s, o3, 10)
          assert length(results) == 3
          assert [{^o3, _} | _] = results
        end

        @tag :stream_phase1
        test "read with count exceeding stream length returns what's available", %{s: s} do
          {:ok, results} = Stream.read(s, :head, 100)
          assert length(results) == 5
        end

        @tag :stream_phase1
        test "read past the head returns []", %{s: s, offsets: offsets} do
          assert {:ok, []} = Stream.read(s, List.last(offsets) + 1, 10)
        end

        @tag :stream_phase1
        test "read with a bad cursor is invalid_offset", %{s: s} do
          assert {:error, %Comn.Errors.ErrorStruct{code: "repo.stream/invalid_offset"}} =
                   Stream.read(s, :sideways, 1)
        end

        @tag :stream_phase1
        test "results pair offset with EventStruct", %{s: s} do
          {:ok, [{offset, event} | _]} = Stream.read(s, :head, 1)
          assert is_integer(offset)
          assert %EventStruct{data: %{n: 1}} = event
        end
      end

      describe "head and tail (#{__MODULE__})" do
        setup ctx, do: %{s: open!(ctx)}

        @tag :stream_phase1
        test "empty stream: head/tail are nil and read returns []", %{s: s} do
          assert {:ok, nil} = Stream.head(s)
          assert {:ok, nil} = Stream.tail(s)
          assert {:ok, []} = Stream.read(s, :head, 10)
          assert {:ok, []} = Stream.read(s, :tail, 10)
        end

        @tag :stream_phase1
        test "head/1 is the latest offset, tail/1 the earliest", %{s: s} do
          {:ok, o1} = Stream.append(s, event(%{n: 1}))
          {:ok, _} = Stream.append(s, event(%{n: 2}))
          {:ok, o3} = Stream.append(s, event(%{n: 3}))
          assert {:ok, ^o3} = Stream.head(s)
          assert {:ok, ^o1} = Stream.tail(s)
        end
      end
    end
  end
end
