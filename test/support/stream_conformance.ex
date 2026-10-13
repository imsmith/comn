defmodule Comn.StreamConformance do
  @moduledoc """
  Shared acceptance spec for `Comn.Repo.Stream` backends, run entirely
  through the public facade so it proves backend fungibility.

  A backend test module does:

      use Comn.StreamConformance

      def open_stream(_ctx) do
        name = :"stream_\#{System.unique_integer([:positive])}"
        {:ok, s} = Comn.Repo.Stream.open(name, backend: :mem)
        {s, fn -> Comn.Repo.Stream.drop(s) end}
      end

  `open_stream/1` receives the ExUnit context and returns a handle plus a
  cleanup function. Any `@moduletag` the backend needs (`:tmp_dir`, `:nats`)
  must be declared **before** the `use` line, since the tests are defined
  at that point. Lifecycle details are the backend module's own tests.

  Phase tags: `:stream_phase1` (append/read/head/tail/Repo verbs),
  `:stream_phase2a` (live subscribe).
  """

  defmacro __using__(_opts) do
    quote location: :keep do
      alias Comn.Events.EventStruct
      alias Comn.Repo.Stream

      defp event(payload \\ %{}, topic \\ "test.event") do
        EventStruct.new(:test, topic, payload)
      end

      defp open!(ctx) do
        {s, cleanup} = open_stream(ctx)
        on_exit(cleanup)
        s
      end

      # ------------------------------------------------------------------
      # Phase 1
      # ------------------------------------------------------------------

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

      describe "Comn.Repo verbs (#{__MODULE__})" do
        setup ctx do
          s = open!(ctx)
          {:ok, _} = Stream.append(s, event(%{n: 1}))
          %{s: s}
        end

        @tag :stream_phase1
        test "describe/1 returns stream metadata", %{s: s} do
          assert {:ok, %{name: name, head: h, tail: t, count: 1, backend: b}} = Stream.describe(s)
          assert name == s.name and h == t and is_atom(b)
        end

        @tag :stream_phase1
        test "get/2 by offset returns the event", %{s: s} do
          {:ok, o} = Stream.head(s)
          assert {:ok, %EventStruct{data: %{n: 1}}} = Stream.get(s, offset: o)
        end

        @tag :stream_phase1
        test "get/2 at an unknown offset returns invalid_offset", %{s: s} do
          assert {:error, %Comn.Errors.ErrorStruct{code: "repo.stream/invalid_offset"}} =
                   Stream.get(s, offset: 999)
        end

        @tag :stream_phase1
        test "set/2 delegates to append", %{s: s} do
          assert {:ok, _offset} = Stream.set(s, event: event(%{n: 99}))
        end

        @tag :stream_phase1
        test "delete/2 returns append_only", %{s: s} do
          assert {:error, %Comn.Errors.ErrorStruct{code: "repo.stream/append_only"}} =
                   Stream.delete(s, key: :anything)
        end

        @tag :stream_phase1
        test "observe/2 streams every {offset, event} in order", %{s: s} do
          {:ok, _} = Stream.append(s, event(%{n: 2}))
          {:ok, _} = Stream.append(s, event(%{n: 3}))
          payloads = Stream.observe(s) |> Enum.map(fn {_o, e} -> e.data.n end)
          assert payloads == [1, 2, 3]
        end
      end

      # ------------------------------------------------------------------
      # Phase 2a: live subscribe
      # ------------------------------------------------------------------

      describe "subscribe (#{__MODULE__})" do
        setup ctx do
          s = open!(ctx)
          %{s: s, name: s.name}
        end

        @tag :stream_phase2a
        test "subscriber receives each append with its offset", %{s: s, name: name} do
          {:ok, _ref} = Stream.subscribe(s)
          {:ok, o1} = Stream.append(s, event(%{n: 1}))
          {:ok, o2} = Stream.append(s, event(%{n: 2}))
          assert_receive {:stream, ^name, ^o1, %EventStruct{data: %{n: 1}}}
          assert_receive {:stream, ^name, ^o2, %EventStruct{data: %{n: 2}}}
        end

        @tag :stream_phase2a
        test "append_many delivers one message per event, in order", %{s: s, name: name} do
          {:ok, _ref} = Stream.subscribe(s)

          {:ok, [o1, o2, o3]} =
            Stream.append_many(s, [event(%{n: 1}), event(%{n: 2}), event(%{n: 3})])

          assert_receive {:stream, ^name, ^o1, %EventStruct{data: %{n: 1}}}
          assert_receive {:stream, ^name, ^o2, %EventStruct{data: %{n: 2}}}
          assert_receive {:stream, ^name, ^o3, %EventStruct{data: %{n: 3}}}
        end

        @tag :stream_phase2a
        test "each append is delivered exactly once", %{s: s, name: name} do
          {:ok, _ref} = Stream.subscribe(s)
          {:ok, o} = Stream.append(s, event())
          assert_receive {:stream, ^name, ^o, _}
          refute_receive {:stream, ^name, ^o, _}, 50
        end

        @tag :stream_phase2a
        test "events appended before subscribing are not delivered", %{s: s, name: name} do
          {:ok, _} = Stream.append(s, event(%{n: :old}))
          {:ok, _ref} = Stream.subscribe(s)
          {:ok, o} = Stream.append(s, event(%{n: :new}))
          assert_receive {:stream, ^name, ^o, %EventStruct{data: %{n: :new}}}
          refute_received {:stream, ^name, _, %EventStruct{data: %{n: :old}}}
        end

        @tag :stream_phase2a
        test "every subscriber receives every append", %{s: s, name: name} do
          parent = self()

          spawn_link(fn ->
            {:ok, _} = Stream.subscribe(s)
            send(parent, :ready)

            receive do
              {:stream, ^name, o, _} -> send(parent, {:other_got, o})
            end
          end)

          assert_receive :ready
          {:ok, _ref} = Stream.subscribe(s)
          {:ok, o} = Stream.append(s, event())
          assert_receive {:stream, ^name, ^o, _}
          assert_receive {:other_got, ^o}
        end

        @tag :stream_phase2a
        test "unsubscribe/2 stops delivery", %{s: s, name: name} do
          {:ok, ref} = Stream.subscribe(s)
          :ok = Stream.unsubscribe(s, ref)
          {:ok, _} = Stream.append(s, event())
          refute_receive {:stream, ^name, _, _}, 50
        end

        @tag :stream_phase2a
        test "a dead subscriber does not break append", %{s: s} do
          pid =
            spawn(fn ->
              {:ok, _} = Stream.subscribe(s)
              :timer.sleep(:infinity)
            end)

          :timer.sleep(10)
          Process.exit(pid, :kill)
          :timer.sleep(10)
          assert {:ok, _} = Stream.append(s, event())
        end

        @tag :stream_phase2a
        test "catch-up recipe: subscribe, then read from last seen offset", %{s: s, name: name} do
          {:ok, [_, last_seen]} = Stream.append_many(s, [event(%{n: 1}), event(%{n: 2})])
          {:ok, _ref} = Stream.subscribe(s)
          {:ok, o3} = Stream.append(s, event(%{n: 3}))

          {:ok, replay} = Stream.read(s, last_seen + 1, 100)
          assert Enum.map(replay, fn {o, _} -> o end) == [o3]
          # the live copy is a duplicate the caller drops by offset
          assert_receive {:stream, ^name, ^o3, _}
        end
      end
    end
  end
end
