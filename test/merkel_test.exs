defmodule Comn.MerkelTest do
  @moduledoc """
  Acceptance test specifications for Comn.Repo.Merkel (the facade) and its
  :mem backend.

  Merkel addresses a fact by its content, keeps it forever, never changes
  it, and can prove it is unchanged. Verbs: put, get, head, verify. Every
  put extends a hash chain; head is the root.

  Phase 1: facade + :mem. Phase 2: :git — test/merkel_git_test.exs.
  """

  use ExUnit.Case, async: true
  use Comn.MerkelConformance
  use Comn.EventSinkConformance, backend: Comn.Repo.Merkel

  doctest Comn.Repo.Merkel
  doctest Comn.Merkel

  alias Comn.Events.EventStruct
  alias Comn.Repo.Merkel

  defp fresh_name, do: :"merkel_#{:erlang.unique_integer([:positive])}"

  def open_merkel(_ctx) do
    {:ok, m} = Merkel.open(fresh_name(), backend: :mem)
    {m, fn -> Merkel.drop(m) end}
  end

  def open_sink(ctx), do: open_merkel(ctx)

  # :mem keeps nodes in a named ETS table keyed by address
  def tamper(%Merkel.Handle{state: table}, address) do
    [{^address, node}] = :ets.lookup(table, address)
    :ets.insert(table, {address, %{node | content: :erlang.term_to_binary(:tampered)}})
    :ok
  end

  describe "facade" do
    @tag :merkel_phase1
    test "look/recon/choices/act behave as a Comn facade" do
      assert is_binary(Merkel.look())
      assert %{type: :facade, extends: Comn.Repo, backends: backends} = Merkel.recon()
      assert :mem in backends and :git in backends
      assert is_map(Merkel.choices())

      assert {:error, %Comn.Errors.ErrorStruct{code: "comn/unknown_action"}} =
               Merkel.act(%{action: :bogus})
    end

    @tag :merkel_phase1
    test "open/2 with an unknown backend is invalid_opts" do
      assert {:error, %Comn.Errors.ErrorStruct{code: "repo.merkel/invalid_opts"}} =
               Merkel.open(fresh_name(), backend: :stone_tablet)
    end
  end

  describe "Comn.Merkel protocol" do
    @tag :merkel_phase1
    test "to_content/1 is deterministic for equal terms" do
      e = EventStruct.new(:test, "proto", %{a: 1, b: 2})
      assert Comn.Merkel.to_content(e) == Comn.Merkel.to_content(e)
      assert is_binary(Comn.Merkel.to_content(e))
    end

    @tag :merkel_phase1
    test "to_content/1 differs for different terms" do
      a = EventStruct.new(:test, "proto", %{n: 1})
      b = EventStruct.new(:test, "proto", %{n: 2})
      refute Comn.Merkel.to_content(a) == Comn.Merkel.to_content(b)
    end

    @tag :merkel_phase1
    test "any term has content" do
      assert is_binary(Comn.Merkel.to_content(%{any: :map}))
      assert Comn.Merkel.to_content("raw bytes") == "raw bytes"
    end
  end

  describe ":mem lifecycle" do
    @tag :merkel_phase1
    test "open/2 twice under the same name returns already_exists" do
      name = fresh_name()
      {:ok, m} = Merkel.open(name, backend: :mem)

      assert {:error, %Comn.Errors.ErrorStruct{code: "repo.merkel/already_exists"}} =
               Merkel.open(name, backend: :mem)

      Merkel.drop(m)
    end

    @tag :merkel_phase1
    test "drop/1 removes everything and is idempotent" do
      {:ok, m} = Merkel.open(fresh_name(), backend: :mem)
      {:ok, _} = Merkel.put(m, entry())
      assert :ok = Merkel.drop(m)
      assert {:error, %Comn.Errors.ErrorStruct{code: "repo.merkel/not_found"}} = Merkel.head(m)
      assert :ok = Merkel.drop(m)
    end
  end
end
