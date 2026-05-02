defmodule Comn.Repo.QueueTest do
  @moduledoc false
  use ExUnit.Case, async: true

  doctest Comn.Repo.Queue

  alias Comn.Errors.Registry
  alias Comn.Repo.Queue
  alias Comn.Repo.Queue.Handle

  setup_all do
    Code.ensure_loaded!(Comn.Repo.Queue.Errors)
    Registry.discover()
    :ok
  end

  describe "open/2" do
    test "rejects unknown backend with :invalid_opts" do
      assert {:error, %{code: "repo.queue/invalid_opts"}} =
               Queue.open(:nope, backend: :nonsense)
    end

    test "rejects unknown discipline with :invalid_opts" do
      assert {:error, %{code: "repo.queue/invalid_opts"}} =
               Queue.open(:nope, backend: :mem, discipline: :random)
    end

    test "defaults to mem + fifo when only name is given" do
      assert {:ok, %Handle{backend: Comn.Repo.Queue.Mem, discipline: :fifo}} =
               Queue.open(:default_test)
    end
  end

  describe "Comn behaviour callbacks" do
    test "look/0" do
      assert is_binary(Queue.look())
    end

    test "recon/0 advertises the operations and that backends are private" do
      r = Queue.recon()
      assert :push in r.callbacks
      assert :pop  in r.callbacks
      assert r.type == :facade
    end
  end
end
