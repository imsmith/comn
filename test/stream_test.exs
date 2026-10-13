defmodule Comn.StreamTest do
  @moduledoc """
  Acceptance test specifications for Comn.Repo.Stream (the facade) and
  its :mem backend.

  Phase 1:  append/read/head/tail + Comn.Repo verbs
  Phase 2a: live subscribe — `{:stream, name, offset, event}`; no replay
  Phase 3:  :sqlite durable backend — test/stream_sqlite_test.exs
  Phase 4:  :jetstream backend — test/stream_jetstream_test.exs

  The backend-agnostic spec lives in `Comn.StreamConformance` and
  `Comn.EventSinkConformance` (test/support) and runs through the facade
  for every backend. This file adds the facade-level and :mem lifecycle tests.
  """

  use ExUnit.Case, async: true
  use Comn.StreamConformance
  use Comn.EventSinkConformance, backend: Comn.Repo.Stream

  doctest Comn.Repo.Stream

  alias Comn.Repo.Stream

  defp fresh_name, do: :"stream_#{:erlang.unique_integer([:positive])}"

  def open_stream(_ctx) do
    {:ok, s} = Stream.open(fresh_name(), backend: :mem)
    {s, fn -> Stream.drop(s) end}
  end

  def open_sink(ctx), do: open_stream(ctx)

  describe "facade" do
    @tag :stream_phase1
    test "look/recon/choices/act behave as a Comn facade" do
      assert is_binary(Stream.look())
      assert %{type: :facade, extends: Comn.Repo, backends: backends} = Stream.recon()
      assert Enum.sort(backends) == [:jetstream, :mem, :sqlite]
      assert %{backends: ["mem", "sqlite", "jetstream"]} = Stream.choices()

      assert {:error, %Comn.Errors.ErrorStruct{code: "comn/unknown_action"}} =
               Stream.act(%{action: :bogus})
    end

    @tag :stream_phase1
    test "open/2 with an unknown backend is invalid_opts" do
      assert {:error, %Comn.Errors.ErrorStruct{code: "repo.stream/invalid_opts"}} =
               Stream.open(fresh_name(), backend: :floppy)
    end

    @tag :stream_phase1
    test "the handle is opaque and carries the name" do
      {:ok, s} = Stream.open(fresh_name(), backend: :mem)
      assert %Comn.Repo.Stream.Handle{name: name} = s
      assert is_atom(name)
      Stream.drop(s)
    end
  end

  describe ":mem lifecycle" do
    @tag :stream_phase1
    test "open/2 twice under the same name returns already_exists" do
      name = fresh_name()
      {:ok, s} = Stream.open(name, backend: :mem)

      assert {:error, %Comn.Errors.ErrorStruct{code: "repo.stream/already_exists"}} =
               Stream.open(name, backend: :mem)

      Stream.drop(s)
    end

    @tag :stream_phase1
    test "drop/1 removes the stream and is idempotent" do
      {:ok, s} = Stream.open(fresh_name(), backend: :mem)
      assert :ok = Stream.drop(s)
      assert {:error, %Comn.Errors.ErrorStruct{code: "repo.stream/not_found"}} = Stream.head(s)
      assert :ok = Stream.drop(s)
    end

    @tag :stream_phase1
    test "close/1 on :mem is drop (nothing is durable)" do
      {:ok, s} = Stream.open(fresh_name(), backend: :mem)
      assert :ok = Stream.close(s)
      assert {:error, _} = Stream.head(s)
    end
  end
end
