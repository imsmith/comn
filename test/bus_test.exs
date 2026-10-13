defmodule Comn.BusTest do
  @moduledoc """
  Acceptance test specifications for Comn.Repo.Bus (ADR-0001 step 5).

  A bus publishes a fact to every current subscriber and retains nothing.
  `set/2` publishes, `observe/2` is a live stream, `get/2` and `delete/2`
  are errors. Subscribers receive `{:bus, name, event}`.

  Backend-agnostic spec: `Comn.EventSinkConformance` with `retains: false`.
  """

  use ExUnit.Case, async: true
  use Comn.EventSinkConformance, backend: Comn.Repo.Bus, retains: false

  doctest Comn.Repo.Bus

  alias Comn.Repo.Bus

  defp fresh_name, do: :"bus_#{:erlang.unique_integer([:positive])}"

  def open_sink(_ctx) do
    {:ok, b} = Bus.open(fresh_name(), backend: :registry)
    {b, fn -> Bus.drop(b) end}
  end

  describe "facade" do
    @tag :bus_phase1
    test "look/recon/choices/act behave as a Comn facade" do
      assert is_binary(Bus.look())
      assert %{type: :facade, extends: Comn.Repo, backends: [:registry]} = Bus.recon()
      assert is_map(Bus.choices())

      assert {:error, %Comn.Errors.ErrorStruct{code: "comn/unknown_action"}} =
               Bus.act(%{action: :bogus})
    end

    @tag :bus_phase1
    test "open/2 with an unknown backend is invalid_opts" do
      assert {:error, %Comn.Errors.ErrorStruct{code: "repo.bus/invalid_opts"}} =
               Bus.open(fresh_name(), backend: :carrier_pigeon)
    end

    @tag :bus_phase1
    test "delete/2 is not retained", %{} do
      {:ok, b} = Bus.open(fresh_name())

      assert {:error, %Comn.Errors.ErrorStruct{code: "repo.bus/not_retained"}} =
               Bus.delete(b, id: "x")
    end
  end

  describe "publish and subscribe" do
    setup ctx do
      b = sink!(ctx)
      %{b: b, name: b.name}
    end

    @tag :bus_phase1
    test "publish with no subscribers is ok", %{b: b} do
      assert :ok = Bus.publish(b, fact())
    end

    @tag :bus_phase1
    test "publish rejects a non-event", %{b: b} do
      assert {:error, %Comn.Errors.ErrorStruct{code: "repo.bus/invalid_event"}} =
               Bus.publish(b, :nope)
    end

    @tag :bus_phase1
    test "a subscriber receives every publish", %{b: b, name: name} do
      {:ok, _ref} = Bus.subscribe(b)
      e1 = fact(%{n: 1})
      e2 = fact(%{n: 2})
      :ok = Bus.publish(b, e1)
      :ok = Bus.publish(b, e2)
      assert_receive {:bus, ^name, ^e1}
      assert_receive {:bus, ^name, ^e2}
    end

    @tag :bus_phase1
    test "events published before subscribing are gone", %{b: b, name: name} do
      :ok = Bus.publish(b, fact(%{n: :old}))
      {:ok, _ref} = Bus.subscribe(b)
      e = fact(%{n: :new})
      :ok = Bus.publish(b, e)
      assert_receive {:bus, ^name, ^e}
      refute_received {:bus, ^name, %{data: %{n: :old}}}
    end

    @tag :bus_phase1
    test "every subscriber receives every publish", %{b: b, name: name} do
      parent = self()

      spawn_link(fn ->
        {:ok, _} = Bus.subscribe(b)
        send(parent, :ready)

        receive do
          {:bus, ^name, e} -> send(parent, {:other_got, e})
        end
      end)

      assert_receive :ready
      {:ok, _} = Bus.subscribe(b)
      e = fact()
      :ok = Bus.publish(b, e)
      assert_receive {:bus, ^name, ^e}
      assert_receive {:other_got, ^e}
    end

    @tag :bus_phase1
    test "subscribe with topic: only delivers that topic", %{b: b, name: name} do
      {:ok, _} = Bus.subscribe(b, topic: "orders.placed")
      hit = fact(%{}, "orders.placed")
      miss = fact(%{}, "orders.cancelled")
      :ok = Bus.publish(b, miss)
      :ok = Bus.publish(b, hit)
      assert_receive {:bus, ^name, ^hit}
      refute_received {:bus, ^name, ^miss}
    end

    @tag :bus_phase1
    test "unsubscribe/2 stops delivery", %{b: b, name: name} do
      {:ok, ref} = Bus.subscribe(b)
      :ok = Bus.unsubscribe(b, ref)
      :ok = Bus.publish(b, fact())
      refute_receive {:bus, ^name, _}, 50
    end

    @tag :bus_phase1
    test "a dead subscriber does not break publish", %{b: b} do
      pid =
        spawn(fn ->
          {:ok, _} = Bus.subscribe(b)
          :timer.sleep(:infinity)
        end)

      :timer.sleep(10)
      Process.exit(pid, :kill)
      :timer.sleep(10)
      assert :ok = Bus.publish(b, fact())
    end

    @tag :bus_phase1
    test "describe/1 reports the subscriber count", %{b: b} do
      assert {:ok, %{subscribers: 0}} = Bus.describe(b)
      {:ok, _} = Bus.subscribe(b)
      assert {:ok, %{name: _, backend: _, subscribers: 1}} = Bus.describe(b)
    end
  end
end
