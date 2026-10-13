defmodule Comn.StreamTest do
  @moduledoc """
  Acceptance test specifications for Comn.Repo.Stream.

  Phase 1:  Behaviour + Mem backend (caller-tracked offsets, append-only)
  Phase 2a: Live subscribe — `{:stream, name, offset, event}` delivered to
            subscriber pids on append; no replay, catch-up is read/3
  Phase 2b: Consumer groups — commit/3 and position/2 so the backend
            remembers how far a named group has processed
  Phase 3:  SQLite durable backend — see test/stream_sqlite_test.exs
  Phase 4:  NATS JetStream adapter — see test/stream_jetstream_test.exs

  The backend-agnostic spec lives in `Comn.StreamConformance`
  (test/support/stream_conformance.ex) and runs against every backend.
  This file holds the behaviour-level tests and the Mem lifecycle.

  To run:
    mix test test/stream_test.exs
  """

  use ExUnit.Case, async: true
  use Comn.StreamConformance, backend: Comn.Repo.Stream.Mem
  use Comn.EventSinkConformance, backend: Comn.Repo.Stream.Mem

  def open_sink(ctx), do: open_stream(ctx)

  doctest Comn.Repo.Stream.Mem

  alias Comn.Repo.Stream, as: StreamBehaviour
  alias Comn.Repo.Stream.Mem

  defp fresh_name, do: :"stream_#{:erlang.unique_integer([:positive])}"

  def open_stream(_ctx) do
    name = fresh_name()
    :ok = Mem.create(name)
    {name, fn -> Mem.drop(name) end}
  end

  # ==========================================================================
  # Behaviour
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

    @tag :stream_phase2a
    @tag :stream_phase2b
    test "subscribe/2, unsubscribe/2, commit/3, position/2 are optional callbacks" do
      optional = StreamBehaviour.behaviour_info(:optional_callbacks)
      assert {:subscribe, 2} in optional
      assert {:unsubscribe, 2} in optional
      assert {:commit, 3} in optional
      assert {:position, 2} in optional
    end

    @tag :stream_phase1
    test "extends Comn.Repo per recon/0 and lists every callback" do
      assert %{extends: Comn.Repo, callbacks: cbs} = StreamBehaviour.recon()

      for cb <- [
            :append,
            :append_many,
            :read,
            :head,
            :tail,
            :subscribe,
            :unsubscribe,
            :commit,
            :position
          ] do
        assert cb in cbs
      end
    end

    @tag :stream_phase1
    test "look/recon/choices/act behave as a behaviour-only Comn module" do
      assert is_binary(StreamBehaviour.look())
      assert is_map(StreamBehaviour.recon())
      assert %{implementations: impls} = StreamBehaviour.choices()
      assert "Mem" in impls and "SQLite" in impls and "JetStream" in impls

      assert {:error, %Comn.Errors.ErrorStruct{code: "comn/behaviour_only"}} =
               StreamBehaviour.act(%{})
    end
  end

  # ==========================================================================
  # Mem lifecycle
  # ==========================================================================

  describe "Mem.create and Mem.drop" do
    @tag :stream_phase1
    test "create/1 with a fresh atom returns :ok" do
      name = fresh_name()
      assert :ok = Mem.create(name)
      Mem.drop(name)
    end

    @tag :stream_phase1
    test "create/1 on an existing name returns already_exists" do
      name = fresh_name()
      :ok = Mem.create(name)

      assert {:error, %Comn.Errors.ErrorStruct{code: "repo.stream/already_exists"}} =
               Mem.create(name)

      Mem.drop(name)
    end

    @tag :stream_phase1
    test "drop/1 removes the stream" do
      name = fresh_name()
      :ok = Mem.create(name)
      assert :ok = Mem.drop(name)
      assert {:error, _} = Mem.head(name)
    end

    @tag :stream_phase2b
    test "drop/1 removes group state" do
      name = fresh_name()
      :ok = Mem.create(name)
      {:ok, o} = Mem.append(name, event())
      :ok = Mem.commit(name, :billing, o)
      :ok = Mem.drop(name)
      :ok = Mem.create(name)
      assert {:ok, nil} = Mem.position(name, :billing)
      Mem.drop(name)
    end
  end
end
