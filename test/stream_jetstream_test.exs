defmodule Comn.StreamJetStreamTest do
  @moduledoc """
  Phase 4: NATS JetStream adapter.

  Needs a JetStream-enabled server. Excluded unless NATS_URL is set:

      podman run -d --name comn-nats -p 4222:4222 docker.io/library/nats:latest -js
      NATS_URL=nats://127.0.0.1:4222 mix test test/stream_jetstream_test.exs

  Runs the shared conformance spec, then the lifecycle and durability
  tests that only make sense against a server.
  """

  use ExUnit.Case, async: false

  # Must precede `use Comn.StreamConformance`: module tags only reach tests
  # defined after them, and the conformance macro defines its tests here.
  @moduletag :nats

  use Comn.StreamConformance, backend: Comn.Repo.Stream.JetStream
  use Comn.EventSinkConformance, backend: Comn.Repo.Stream.JetStream

  def open_sink(ctx), do: open_stream(ctx)

  alias Comn.Repo.Stream.JetStream

  @conn :comn_test_gnat

  setup_all do
    uri = URI.parse(System.get_env("NATS_URL", "nats://127.0.0.1:4222"))
    {:ok, _} = Gnat.start_link(%{host: uri.host, port: uri.port}, name: @conn)
    :ok
  end

  defp fresh_name, do: :"js_stream_#{:erlang.unique_integer([:positive])}"

  def open_stream(_ctx) do
    name = fresh_name()
    :ok = JetStream.open(name, conn: @conn)
    {name, fn -> JetStream.drop(name) end}
  end

  describe "JetStream lifecycle" do
    @tag :stream_phase4
    test "open/2 requires a :conn" do
      assert {:error, %Comn.Errors.ErrorStruct{code: "repo.stream/invalid_opts"}} =
               JetStream.open(fresh_name(), [])
    end

    @tag :stream_phase4
    test "open/2 twice under the same name returns already_exists" do
      name = fresh_name()
      :ok = JetStream.open(name, conn: @conn)

      assert {:error, %Comn.Errors.ErrorStruct{code: "repo.stream/already_exists"}} =
               JetStream.open(name, conn: @conn)

      JetStream.drop(name)
    end

    @tag :stream_phase4
    test "close/1 stops the local process, drop/1 also deletes the server stream" do
      name = fresh_name()
      :ok = JetStream.open(name, conn: @conn)
      {:ok, _} = JetStream.append(name, event())
      js_name = JetStream.js_stream_name(name)

      assert :ok = JetStream.close(name)

      assert {:error, %Comn.Errors.ErrorStruct{code: "repo.stream/not_found"}} =
               JetStream.head(name)

      assert {:ok, _} = Gnat.Jetstream.API.Stream.info(@conn, js_name)

      :ok = JetStream.open(name, conn: @conn)
      assert :ok = JetStream.drop(name)
      assert {:error, _} = Gnat.Jetstream.API.Stream.info(@conn, js_name)
      assert :ok = JetStream.drop(name)
    end
  end

  describe "JetStream durability" do
    @tag :stream_phase4
    test "events, offsets and group positions survive close and reopen" do
      name = fresh_name()
      :ok = JetStream.open(name, conn: @conn)

      {:ok, [o1, o2, o3]} = JetStream.append_many(name, Enum.map(1..3, &event(%{n: &1})))
      :ok = JetStream.commit(name, :billing, o2)
      :ok = JetStream.close(name)

      :ok = JetStream.open(name, conn: @conn)
      assert {:ok, ^o3} = JetStream.head(name)
      assert {:ok, ^o1} = JetStream.tail(name)
      assert {:ok, ^o2} = JetStream.position(name, :billing)

      {:ok, events} = JetStream.read(name, :head, 10)
      assert Enum.map(events, fn {_o, e} -> e.data.n end) == [1, 2, 3]

      {:ok, o4} = JetStream.append(name, event(%{n: 4}))
      assert o4 > o3
      JetStream.drop(name)
    end

    @tag :stream_phase4
    test "offsets are JetStream stream sequences" do
      name = fresh_name()
      :ok = JetStream.open(name, conn: @conn)
      {:ok, o} = JetStream.append(name, event())
      {:ok, info} = Gnat.Jetstream.API.Stream.info(@conn, JetStream.js_stream_name(name))
      assert info.state.last_seq == o
      JetStream.drop(name)
    end
  end
end
