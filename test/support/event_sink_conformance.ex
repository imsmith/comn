defmodule Comn.EventSinkConformance do
  @moduledoc """
  The cross-shape spec behind ADR-0001: every Repo shape is an event sink.

  A backend test module does:

      use Comn.EventSinkConformance, backend: Comn.Repo.Table.ETS

      def open_sink(_ctx) do
        name = :"t_\#{System.unique_integer([:positive])}"
        :ok = Comn.Repo.Table.ETS.create(name)
        {name, fn -> Comn.Repo.Table.ETS.drop(name) end}
      end

  `open_sink/1` receives the ExUnit context and returns a resource handle
  plus a cleanup function. The spec then exercises only the `Comn.Repo`
  verbs, in their canonical event forms:

  - `set(h, event: %EventStruct{})` accepts any event
  - `get(h, id: event.id)` returns it where the medium retains it
  - `observe(h, as: :events)` enumerates stored events

  Shapes whose `set/2` returns a new handle (immutable structs, e.g. Graph)
  are threaded through `after_set/2`. Any `@moduletag` the backend needs must
  precede the `use` line.
  """

  defmacro __using__(opts) do
    backend = Keyword.fetch!(opts, :backend)

    quote location: :keep do
      alias Comn.Errors.ErrorStruct
      alias Comn.Events.EventStruct

      @sink unquote(backend)

      defp fact(data \\ %{}, topic \\ "sink.test") do
        EventStruct.new(:domain, topic, data)
      end

      defp sink!(ctx) do
        {h, cleanup} = open_sink(ctx)
        on_exit(cleanup)
        h
      end

      # set/2 may return :ok, {:ok, offset-or-similar}, or {:ok, new_handle}
      # for immutable shapes. Keep the handle current either way.
      defp after_set(h, :ok), do: h
      defp after_set(%mod{} = _h, {:ok, %mod{} = new_h}), do: new_h
      defp after_set(h, {:ok, _}), do: h

      defp put!(h, event) do
        result = @sink.set(h, event: event)
        assert match?(:ok, result) or match?({:ok, _}, result), inspect(result)
        after_set(h, result)
      end

      describe "#{inspect(@sink)} as an event sink" do
        setup ctx, do: %{h: sink!(ctx)}

        @tag :event_sink
        test "set/2 accepts an event", %{h: h} do
          put!(h, fact(%{n: 1}))
        end

        @tag :event_sink
        test "set/2 rejects a non-event under :event", %{h: h} do
          assert {:error, %ErrorStruct{}} = @sink.set(h, event: %{not: "an event"})
        end

        @tag :event_sink
        test "get/2 by id returns the same event", %{h: h} do
          e = fact(%{n: 1})
          h = put!(h, e)
          assert {:ok, ^e} = @sink.get(h, id: e.id)
        end

        @tag :event_sink
        test "get/2 by unknown id is an error", %{h: h} do
          h = put!(h, fact())
          assert {:error, %ErrorStruct{}} = @sink.get(h, id: "no-such-id")
        end

        @tag :event_sink
        test "observe/2 as events yields every stored event", %{h: h} do
          events = for n <- 1..3, do: fact(%{n: n})
          h = Enum.reduce(events, h, fn e, h -> put!(h, e) end)
          seen = @sink.observe(h, as: :events) |> Enum.to_list()
          assert length(seen) == 3
          assert Enum.all?(events, &(&1 in seen))
        end

        @tag :event_sink
        test "system events are carried, not policed", %{h: h} do
          e = EventStruct.new(:system, "sink.system", %{})
          h = put!(h, e)
          assert {:ok, ^e} = @sink.get(h, id: e.id)
        end
      end
    end
  end
end
