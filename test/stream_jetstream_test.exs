defmodule Comn.StreamJetStreamTest do
  @moduledoc """
  Phase 4: :jetstream backend, through the facade.

  Needs a JetStream-enabled server. Excluded unless NATS_URL is set:

      podman run -d --name comn-nats -p 4222:4222 docker.io/library/nats:latest -js
      NATS_URL=nats://127.0.0.1:4222 mix test test/stream_jetstream_test.exs
  """

  use ExUnit.Case, async: false

  # Must precede the conformance `use` lines: module tags only reach tests
  # defined after them.
  @moduletag :nats

  use Comn.StreamConformance
  use Comn.EventSinkConformance, backend: Comn.Repo.Stream

  alias Comn.Repo.Stream
  alias Comn.Repo.Stream.JetStream

  @conn :comn_test_gnat

  setup_all do
    uri = URI.parse(System.get_env("NATS_URL", "nats://127.0.0.1:4222"))
    {:ok, _} = Gnat.start_link(%{host: uri.host, port: uri.port}, name: @conn)
    :ok
  end

  defp fresh_name, do: :"js_stream_#{:erlang.unique_integer([:positive])}"

  def open_stream(_ctx) do
    {:ok, s} = Stream.open(fresh_name(), backend: :jetstream, conn: @conn)
    {s, fn -> Stream.drop(s) end}
  end

  def open_sink(ctx), do: open_stream(ctx)

  describe ":jetstream lifecycle" do
    @tag :stream_phase4
    test "open/2 requires a :conn" do
      assert {:error, %Comn.Errors.ErrorStruct{code: "repo.stream/invalid_opts"}} =
               Stream.open(fresh_name(), backend: :jetstream)
    end

    @tag :stream_phase4
    test "open/2 twice under the same name returns already_exists" do
      name = fresh_name()
      {:ok, s} = Stream.open(name, backend: :jetstream, conn: @conn)

      assert {:error, %Comn.Errors.ErrorStruct{code: "repo.stream/already_exists"}} =
               Stream.open(name, backend: :jetstream, conn: @conn)

      Stream.drop(s)
    end

    @tag :stream_phase4
    test "close/1 stops the local process, drop/1 also deletes the server stream" do
      name = fresh_name()
      {:ok, s0} = Stream.open(name, backend: :jetstream, conn: @conn)
      {:ok, _} = Stream.append(s0, event())
      js_name = JetStream.js_stream_name(name)

      assert :ok = Stream.close(s0)
      assert {:error, %Comn.Errors.ErrorStruct{code: "repo.stream/not_found"}} = Stream.head(s0)
      assert {:ok, _} = Gnat.Jetstream.API.Stream.info(@conn, js_name)

      {:ok, s} = Stream.open(name, backend: :jetstream, conn: @conn)
      assert :ok = Stream.drop(s)
      assert {:error, _} = Gnat.Jetstream.API.Stream.info(@conn, js_name)
      assert :ok = Stream.drop(s)
    end
  end

  describe ":jetstream durability" do
    @tag :stream_phase4
    test "events and offsets survive close and reopen" do
      name = fresh_name()
      {:ok, s0} = Stream.open(name, backend: :jetstream, conn: @conn)
      {:ok, [o1, _, o3]} = Stream.append_many(s0, Enum.map(1..3, &event(%{n: &1})))
      :ok = Stream.close(s0)

      {:ok, s} = Stream.open(name, backend: :jetstream, conn: @conn)
      assert {:ok, ^o3} = Stream.head(s)
      assert {:ok, ^o1} = Stream.tail(s)
      {:ok, events} = Stream.read(s, :head, 10)
      assert Enum.map(events, fn {_o, e} -> e.data.n end) == [1, 2, 3]
      {:ok, o4} = Stream.append(s, event(%{n: 4}))
      assert o4 > o3
      Stream.drop(s)
    end

    @tag :stream_phase4
    test "offsets are JetStream stream sequences" do
      {:ok, s} = Stream.open(fresh_name(), backend: :jetstream, conn: @conn)
      {:ok, o} = Stream.append(s, event())
      {:ok, info} = Gnat.Jetstream.API.Stream.info(@conn, JetStream.js_stream_name(s.name))
      assert info.state.last_seq == o
      Stream.drop(s)
    end
  end
end
