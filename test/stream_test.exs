defmodule Comn.StreamTest do
  @moduledoc """
  Acceptance test specifications for Comn.Repo.Stream.

  Phase 1: Behaviour + Mem backend (caller-tracked offsets, append-only)

  Future phases (out of scope here):
  - Phase 2: Live subscribe / consumer-group offset tracking
  - Phase 3: File-backed durable backend
  - Phase 4: Kafka / NATS JetStream adapters

  To run:
    mix test test/stream_test.exs --include stream_phase1
  """

  use ExUnit.Case, async: true

  doctest Comn.Repo.Stream.Mem

  alias Comn.Events.EventStruct
  alias Comn.Repo.Stream, as: StreamBehaviour
  alias Comn.Repo.Stream.Mem

  # Helpers

  defp fresh_name, do: :"stream_#{:erlang.unique_integer([:positive])}"

  defp event(payload \\ %{}, topic \\ "test.event") do
    EventStruct.new(:test, topic, payload)
  end

  # ==========================================================================
  # Phase 1: Comn.Repo.Stream behaviour
  # ==========================================================================

  describe "Comn.Repo.Stream behaviour" do
    @tag :stream_phase1
    test "defines append/2, append_many/2, read/3, head/1, tail/1 as callbacks" do
      callbacks = StreamBehaviour.behaviour_info(:callbacks)
      assert {:append, 2} in callbacks
      assert {:append_many, 2} in callbacks
      assert {:read, 3} in callbacks
      assert {:head, 1} in callbacks
      assert {:tail, 1} in callbacks
    end

    @tag :stream_phase1
    test "extends Comn.Repo per recon/0" do
      assert %{extends: Comn.Repo} = StreamBehaviour.recon()
    end

    @tag :stream_phase1
    test "look/recon/choices/act behave as a behaviour-only Comn module" do
      assert is_binary(StreamBehaviour.look())
      assert is_map(StreamBehaviour.recon())
      assert is_map(StreamBehaviour.choices())
      assert {:error, :behaviour_only} = StreamBehaviour.act(%{})
    end
  end

  # ==========================================================================
  # Phase 1: Mem backend
  # ==========================================================================

  describe "Mem.create and Mem.drop" do
    @tag :stream_phase1
    test "create/1 with a fresh atom returns :ok" do
      name = fresh_name()
      assert :ok = Mem.create(name)
      Mem.drop(name)
    end

    @tag :stream_phase1
    test "create/1 on an existing name returns error" do
      name = fresh_name()
      :ok = Mem.create(name)
      assert {:error, _} = Mem.create(name)
      Mem.drop(name)
    end

    @tag :stream_phase1
    test "drop/1 removes the stream" do
      name = fresh_name()
      :ok = Mem.create(name)
      assert :ok = Mem.drop(name)
      assert {:error, _} = Mem.head(name)
    end
  end

  describe "Mem.append" do
    setup do
      name = fresh_name()
      :ok = Mem.create(name)
      on_exit(fn -> Mem.drop(name) end)
      {:ok, name: name}
    end

    @tag :stream_phase1
    test "append/2 returns monotonically increasing offsets", %{name: name} do
      {:ok, o1} = Mem.append(name, event(%{n: 1}))
      {:ok, o2} = Mem.append(name, event(%{n: 2}))
      {:ok, o3} = Mem.append(name, event(%{n: 3}))
      assert o1 < o2 and o2 < o3
    end

    @tag :stream_phase1
    test "append/2 on a non-EventStruct returns invalid_event error", %{name: name} do
      assert {:error, %Comn.Errors.ErrorStruct{code: "repo.stream/invalid_event"}} =
               Mem.append(name, %{not: "an event"})
    end

    @tag :stream_phase1
    test "append/2 on unknown stream returns not_found error" do
      assert {:error, %Comn.Errors.ErrorStruct{code: "repo.stream/not_found"}} =
               Mem.append(:nonexistent_stream, event())
    end

    @tag :stream_phase1
    test "append_many/2 returns offsets in input order", %{name: name} do
      events = for n <- 1..5, do: event(%{n: n})
      {:ok, offsets} = Mem.append_many(name, events)
      assert length(offsets) == 5
      assert offsets == Enum.sort(offsets)
    end
  end

  describe "Mem.read" do
    setup do
      name = fresh_name()
      :ok = Mem.create(name)
      events = for n <- 1..5, do: event(%{n: n})
      {:ok, offsets} = Mem.append_many(name, events)
      on_exit(fn -> Mem.drop(name) end)
      {:ok, name: name, offsets: offsets, events: events}
    end

    @tag :stream_phase1
    test "read from :head returns events from earliest offset", %{name: name} do
      {:ok, results} = Mem.read(name, :head, 3)
      assert length(results) == 3
      [{_o, e} | _] = results
      assert e.data.n == 1
    end

    @tag :stream_phase1
    test "read from :tail returns last N events", %{name: name} do
      {:ok, results} = Mem.read(name, :tail, 2)
      assert length(results) == 2
      payloads = Enum.map(results, fn {_o, e} -> e.data.n end)
      assert payloads == [4, 5]
    end

    @tag :stream_phase1
    test "read from explicit offset returns events at and after offset", %{name: name, offsets: [_, _, o3 | _]} do
      {:ok, results} = Mem.read(name, o3, 10)
      assert length(results) == 3
      [{first_offset, _} | _] = results
      assert first_offset == o3
    end

    @tag :stream_phase1
    test "read with count exceeding stream length returns what's available", %{name: name} do
      {:ok, results} = Mem.read(name, :head, 100)
      assert length(results) == 5
    end

    @tag :stream_phase1
    test "read on empty stream returns []" do
      name = fresh_name()
      :ok = Mem.create(name)
      assert {:ok, []} = Mem.read(name, :head, 10)
      Mem.drop(name)
    end

    @tag :stream_phase1
    test "results pair offset with EventStruct", %{name: name} do
      {:ok, [{offset, event} | _]} = Mem.read(name, :head, 1)
      assert is_integer(offset)
      assert %EventStruct{} = event
    end
  end

  describe "Mem.head and Mem.tail" do
    @tag :stream_phase1
    test "head/1 and tail/1 on empty stream return nil" do
      name = fresh_name()
      :ok = Mem.create(name)
      assert {:ok, nil} = Mem.head(name)
      assert {:ok, nil} = Mem.tail(name)
      Mem.drop(name)
    end

    @tag :stream_phase1
    test "head/1 returns the latest offset, tail/1 the earliest" do
      name = fresh_name()
      :ok = Mem.create(name)
      {:ok, o1} = Mem.append(name, event(%{n: 1}))
      {:ok, _o2} = Mem.append(name, event(%{n: 2}))
      {:ok, o3} = Mem.append(name, event(%{n: 3}))
      assert {:ok, ^o3} = Mem.head(name)
      assert {:ok, ^o1} = Mem.tail(name)
      Mem.drop(name)
    end

    @tag :stream_phase1
    test "head/1 on missing stream returns not_found" do
      assert {:error, %Comn.Errors.ErrorStruct{code: "repo.stream/not_found"}} =
               Mem.head(:no_such_stream)
    end
  end

  describe "Mem implements Comn.Repo verbs" do
    setup do
      name = fresh_name()
      :ok = Mem.create(name)
      {:ok, _} = Mem.append(name, event(%{n: 1}))
      on_exit(fn -> Mem.drop(name) end)
      {:ok, name: name}
    end

    @tag :stream_phase1
    test "describe/1 returns stream metadata", %{name: name} do
      assert {:ok, %{name: ^name, head: _, tail: _, count: 1}} = Mem.describe(name)
    end

    @tag :stream_phase1
    test "set/2 delegates to append", %{name: name} do
      assert {:ok, _offset} = Mem.set(name, event: event(%{n: 99}))
    end

    @tag :stream_phase1
    test "delete/2 returns error (append-only invariant)", %{name: name} do
      assert {:error, _} = Mem.delete(name, key: :anything)
    end

    @tag :stream_phase1
    test "observe/2 returns a stream of all events in order", %{name: name} do
      {:ok, _} = Mem.append(name, event(%{n: 2}))
      {:ok, _} = Mem.append(name, event(%{n: 3}))
      events = Mem.observe(name, []) |> Enum.to_list()
      payloads = Enum.map(events, fn {_o, e} -> e.data.n end)
      assert payloads == [1, 2, 3]
    end
  end

  describe "Mem implements Comn behaviour" do
    @tag :stream_phase1
    test "look/recon/choices/act all return expected types" do
      assert is_binary(Mem.look())
      assert is_map(Mem.recon())
      assert is_map(Mem.choices())
    end
  end
end
