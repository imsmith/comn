defmodule Comn.StreamConformance.Sink do
  @moduledoc """
  The sink half of `Comn.StreamConformance`: the stream as a `Comn.Repo`
  (describe/get/set/delete/observe, `:stream_phase1`) and live delivery to
  subscribers (`:stream_phase2a`). Use it through `Comn.StreamConformance`,
  which supplies `event/2` and `open!/1`.
  """

  defmacro __using__(_opts) do
    quote location: :keep do
      alias Comn.Events.EventStruct
      alias Comn.Repo.Stream

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
          payloads = s |> Stream.observe() |> Enum.map(fn {_o, e} -> e.data.n end)
          assert payloads == [1, 2, 3]
        end
      end

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
