defmodule Comn.StreamConformance do
  @moduledoc """
  Shared acceptance spec for `Comn.Repo.Stream` backends.

  A backend test module does:

      use Comn.StreamConformance, backend: Comn.Repo.Stream.Mem

      def open_stream(_ctx) do
        name = :"stream_\#{System.unique_integer([:positive])}"
        :ok = Comn.Repo.Stream.Mem.create(name)
        {name, fn -> Comn.Repo.Stream.Mem.drop(name) end}
      end

  `open_stream/1` receives the ExUnit context and returns the stream name
  plus a cleanup function. Any `@moduletag` the backend needs (`:tmp_dir`,
  `:nats`) must be declared **before** the `use` line, since the tests are
  defined at that point. Everything below is exercised through the
  behaviour callbacks only; lifecycle verbs (`create`/`open`/`drop`) are
  backend-specific and tested in the backend's own module.

  Phase tags: `:stream_phase1` (append/read/head/tail/Repo verbs),
  `:stream_phase2a` (live subscribe), `:stream_phase2b` (consumer groups).
  """

  defmacro __using__(opts) do
    backend = Keyword.fetch!(opts, :backend)

    quote location: :keep do
      alias Comn.Events.EventStruct

      @backend unquote(backend)

      defp event(payload \\ %{}, topic \\ "test.event") do
        EventStruct.new(:test, topic, payload)
      end

      defp open!(ctx) do
        {name, cleanup} = open_stream(ctx)
        on_exit(cleanup)
        name
      end

      # ------------------------------------------------------------------
      # Phase 1
      # ------------------------------------------------------------------

      describe "#{inspect(@backend)} append" do
        setup ctx, do: %{name: open!(ctx)}

        @tag :stream_phase1
        test "append/2 returns monotonically increasing offsets", %{name: name} do
          {:ok, o1} = @backend.append(name, event(%{n: 1}))
          {:ok, o2} = @backend.append(name, event(%{n: 2}))
          {:ok, o3} = @backend.append(name, event(%{n: 3}))
          assert o1 < o2 and o2 < o3
        end

        @tag :stream_phase1
        test "append/2 on a non-EventStruct returns invalid_event", %{name: name} do
          assert {:error, %Comn.Errors.ErrorStruct{code: "repo.stream/invalid_event"}} =
                   @backend.append(name, %{not: "an event"})
        end

        @tag :stream_phase1
        test "append/2 on unknown stream returns not_found" do
          assert {:error, %Comn.Errors.ErrorStruct{code: "repo.stream/not_found"}} =
                   @backend.append(:nonexistent_stream, event())
        end

        @tag :stream_phase1
        test "append_many/2 returns offsets in input order", %{name: name} do
          events = for n <- 1..5, do: event(%{n: n})
          {:ok, offsets} = @backend.append_many(name, events)
          assert length(offsets) == 5
          assert offsets == Enum.sort(offsets)
        end

        @tag :stream_phase1
        test "append_many/2 with one bad event appends nothing", %{name: name} do
          assert {:error, %Comn.Errors.ErrorStruct{code: "repo.stream/invalid_event"}} =
                   @backend.append_many(name, [event(), :bad])

          assert {:ok, nil} = @backend.head(name)
        end
      end

      describe "#{inspect(@backend)} read" do
        setup ctx do
          name = open!(ctx)
          events = for n <- 1..5, do: event(%{n: n})
          {:ok, offsets} = @backend.append_many(name, events)
          %{name: name, offsets: offsets}
        end

        @tag :stream_phase1
        test "read from :head returns the first N events", %{name: name} do
          {:ok, results} = @backend.read(name, :head, 3)
          assert Enum.map(results, fn {_o, e} -> e.data.n end) == [1, 2, 3]
        end

        @tag :stream_phase1
        test "read from :tail returns the last N events", %{name: name} do
          {:ok, results} = @backend.read(name, :tail, 2)
          assert Enum.map(results, fn {_o, e} -> e.data.n end) == [4, 5]
        end

        @tag :stream_phase1
        test "read from an explicit offset returns events at and after it",
             %{name: name, offsets: [_, _, o3 | _]} do
          {:ok, results} = @backend.read(name, o3, 10)
          assert length(results) == 3
          assert [{^o3, _} | _] = results
        end

        @tag :stream_phase1
        test "read with count exceeding stream length returns what's available", %{name: name} do
          {:ok, results} = @backend.read(name, :head, 100)
          assert length(results) == 5
        end

        @tag :stream_phase1
        test "read past the head returns []", %{name: name, offsets: offsets} do
          assert {:ok, []} = @backend.read(name, List.last(offsets) + 1, 10)
        end

        @tag :stream_phase1
        test "results pair offset with EventStruct", %{name: name} do
          {:ok, [{offset, event} | _]} = @backend.read(name, :head, 1)
          assert is_integer(offset)
          assert %EventStruct{data: %{n: 1}} = event
        end
      end

      describe "#{inspect(@backend)} head and tail" do
        setup ctx, do: %{name: open!(ctx)}

        @tag :stream_phase1
        test "empty stream: head/tail are nil and read returns []", %{name: name} do
          assert {:ok, nil} = @backend.head(name)
          assert {:ok, nil} = @backend.tail(name)
          assert {:ok, []} = @backend.read(name, :head, 10)
        end

        @tag :stream_phase1
        test "head/1 is the latest offset, tail/1 the earliest", %{name: name} do
          {:ok, o1} = @backend.append(name, event(%{n: 1}))
          {:ok, _} = @backend.append(name, event(%{n: 2}))
          {:ok, o3} = @backend.append(name, event(%{n: 3}))
          assert {:ok, ^o3} = @backend.head(name)
          assert {:ok, ^o1} = @backend.tail(name)
        end

        @tag :stream_phase1
        test "head/1 on missing stream returns not_found" do
          assert {:error, %Comn.Errors.ErrorStruct{code: "repo.stream/not_found"}} =
                   @backend.head(:no_such_stream)
        end
      end

      describe "#{inspect(@backend)} Comn.Repo verbs" do
        setup ctx do
          name = open!(ctx)
          {:ok, _} = @backend.append(name, event(%{n: 1}))
          %{name: name}
        end

        @tag :stream_phase1
        test "describe/1 returns stream metadata", %{name: name} do
          assert {:ok, %{name: ^name, head: h, tail: t, count: 1}} = @backend.describe(name)
          assert h == t
        end

        @tag :stream_phase1
        test "get/2 by offset returns the event", %{name: name} do
          {:ok, o} = @backend.head(name)
          assert {:ok, %EventStruct{data: %{n: 1}}} = @backend.get(name, offset: o)
        end

        @tag :stream_phase1
        test "get/2 at an unknown offset returns invalid_offset", %{name: name} do
          assert {:error, %Comn.Errors.ErrorStruct{code: "repo.stream/invalid_offset"}} =
                   @backend.get(name, offset: 999)
        end

        @tag :stream_phase1
        test "set/2 delegates to append", %{name: name} do
          assert {:ok, _offset} = @backend.set(name, event: event(%{n: 99}))
        end

        @tag :stream_phase1
        test "delete/2 returns append_only", %{name: name} do
          assert {:error, %Comn.Errors.ErrorStruct{code: "repo.stream/append_only"}} =
                   @backend.delete(name, key: :anything)
        end

        @tag :stream_phase1
        test "observe/2 streams every event in order", %{name: name} do
          {:ok, _} = @backend.append(name, event(%{n: 2}))
          {:ok, _} = @backend.append(name, event(%{n: 3}))
          payloads = @backend.observe(name, []) |> Enum.map(fn {_o, e} -> e.data.n end)
          assert payloads == [1, 2, 3]
        end

        @tag :stream_phase1
        test "look/recon/choices behave as a Comn implementation" do
          assert is_binary(@backend.look())
          assert %{type: :implementation, implements: Comn.Repo.Stream} = @backend.recon()
          assert is_map(@backend.choices())

          assert {:error, %Comn.Errors.ErrorStruct{code: "comn/unknown_action"}} =
                   @backend.act(%{action: :bogus})
        end
      end

      # ------------------------------------------------------------------
      # Phase 2a: live subscribe
      # ------------------------------------------------------------------

      describe "#{inspect(@backend)} subscribe" do
        setup ctx, do: %{name: open!(ctx)}

        @tag :stream_phase2a
        test "subscriber receives each append with its offset", %{name: name} do
          {:ok, _ref} = @backend.subscribe(name, [])
          {:ok, o1} = @backend.append(name, event(%{n: 1}))
          {:ok, o2} = @backend.append(name, event(%{n: 2}))
          assert_receive {:stream, ^name, ^o1, %EventStruct{data: %{n: 1}}}
          assert_receive {:stream, ^name, ^o2, %EventStruct{data: %{n: 2}}}
        end

        @tag :stream_phase2a
        test "append_many delivers one message per event, in order", %{name: name} do
          {:ok, _ref} = @backend.subscribe(name, [])

          {:ok, [o1, o2, o3]} =
            @backend.append_many(name, [event(%{n: 1}), event(%{n: 2}), event(%{n: 3})])

          assert_receive {:stream, ^name, ^o1, %EventStruct{data: %{n: 1}}}
          assert_receive {:stream, ^name, ^o2, %EventStruct{data: %{n: 2}}}
          assert_receive {:stream, ^name, ^o3, %EventStruct{data: %{n: 3}}}
        end

        @tag :stream_phase2a
        test "events appended before subscribing are not delivered", %{name: name} do
          {:ok, _} = @backend.append(name, event(%{n: :old}))
          {:ok, _ref} = @backend.subscribe(name, [])
          {:ok, o} = @backend.append(name, event(%{n: :new}))
          assert_receive {:stream, ^name, ^o, %EventStruct{data: %{n: :new}}}
          refute_received {:stream, ^name, _, %EventStruct{data: %{n: :old}}}
        end

        @tag :stream_phase2a
        test "every subscriber receives every append", %{name: name} do
          parent = self()

          spawn_link(fn ->
            {:ok, _} = @backend.subscribe(name, [])
            send(parent, :ready)

            receive do
              {:stream, ^name, o, _} -> send(parent, {:other_got, o})
            end
          end)

          assert_receive :ready
          {:ok, _ref} = @backend.subscribe(name, [])
          {:ok, o} = @backend.append(name, event())
          assert_receive {:stream, ^name, ^o, _}
          assert_receive {:other_got, ^o}
        end

        @tag :stream_phase2a
        test "unsubscribe/2 stops delivery", %{name: name} do
          {:ok, ref} = @backend.subscribe(name, [])
          :ok = @backend.unsubscribe(name, ref)
          {:ok, _} = @backend.append(name, event())
          refute_receive {:stream, ^name, _, _}, 50
        end

        @tag :stream_phase2a
        test "a dead subscriber does not break append", %{name: name} do
          pid =
            spawn(fn ->
              {:ok, _} = @backend.subscribe(name, [])
              :timer.sleep(:infinity)
            end)

          :timer.sleep(10)
          Process.exit(pid, :kill)
          :timer.sleep(10)
          assert {:ok, _} = @backend.append(name, event())
        end

        @tag :stream_phase2a
        test "subscribe/2 on a missing stream returns not_found" do
          assert {:error, %Comn.Errors.ErrorStruct{code: "repo.stream/not_found"}} =
                   @backend.subscribe(:no_such_stream, [])
        end

        @tag :stream_phase2a
        test "catch-up recipe: subscribe, then read from last seen offset", %{name: name} do
          {:ok, [_, last_seen]} = @backend.append_many(name, [event(%{n: 1}), event(%{n: 2})])

          {:ok, _ref} = @backend.subscribe(name, [])
          {:ok, o3} = @backend.append(name, event(%{n: 3}))

          {:ok, replay} = @backend.read(name, last_seen + 1, 100)
          assert Enum.map(replay, fn {o, _} -> o end) == [o3]

          # the live copy is a duplicate the caller drops by offset
          assert_receive {:stream, ^name, ^o3, _}
        end
      end

      # ------------------------------------------------------------------
      # Phase 2b: consumer groups
      # ------------------------------------------------------------------

      describe "#{inspect(@backend)} consumer groups" do
        setup ctx, do: %{name: open!(ctx)}

        @tag :stream_phase2b
        test "position/2 is nil before any commit", %{name: name} do
          assert {:ok, nil} = @backend.position(name, :billing)
        end

        @tag :stream_phase2b
        test "commit/3 then position/2 round-trips", %{name: name} do
          {:ok, o} = @backend.append(name, event())
          assert :ok = @backend.commit(name, :billing, o)
          assert {:ok, ^o} = @backend.position(name, :billing)
        end

        @tag :stream_phase2b
        test "a later commit overwrites the earlier one", %{name: name} do
          {:ok, [o1, o2]} = @backend.append_many(name, [event(), event()])
          :ok = @backend.commit(name, :billing, o1)
          :ok = @backend.commit(name, :billing, o2)
          assert {:ok, ^o2} = @backend.position(name, :billing)
        end

        @tag :stream_phase2b
        test "groups are independent", %{name: name} do
          {:ok, [o1, o2]} = @backend.append_many(name, [event(), event()])
          :ok = @backend.commit(name, :billing, o1)
          :ok = @backend.commit(name, "audit", o2)
          assert {:ok, ^o1} = @backend.position(name, :billing)
          assert {:ok, ^o2} = @backend.position(name, "audit")
        end

        @tag :stream_phase2b
        test "committing an offset the stream never issued errors", %{name: name} do
          {:ok, _} = @backend.append(name, event())

          assert {:error, %Comn.Errors.ErrorStruct{code: "repo.stream/invalid_offset"}} =
                   @backend.commit(name, :billing, 99)

          assert {:ok, nil} = @backend.position(name, :billing)
        end

        @tag :stream_phase2b
        test "commit/3 and position/2 on a missing stream return not_found" do
          assert {:error, %Comn.Errors.ErrorStruct{code: "repo.stream/not_found"}} =
                   @backend.commit(:no_such_stream, :billing, 1)

          assert {:error, %Comn.Errors.ErrorStruct{code: "repo.stream/not_found"}} =
                   @backend.position(:no_such_stream, :billing)
        end

        @tag :stream_phase2b
        test "consumer loop processes every event exactly once across runs", %{name: name} do
          {:ok, _} = @backend.append_many(name, Enum.map(1..5, &event(%{n: &1})))

          run = fn ->
            {:ok, pos} = @backend.position(name, :billing)
            from = if pos, do: pos + 1, else: :head
            {:ok, batch} = @backend.read(name, from, 2)

            for {o, e} <- batch do
              :ok = @backend.commit(name, :billing, o)
              e.data.n
            end
          end

          assert run.() == [1, 2]
          assert run.() == [3, 4]
          assert run.() == [5]
          {:ok, _} = @backend.append_many(name, Enum.map(6..7, &event(%{n: &1})))
          assert run.() == [6, 7]
          assert run.() == []
        end
      end
    end
  end
end
