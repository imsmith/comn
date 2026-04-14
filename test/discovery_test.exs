defmodule Comn.DiscoveryTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias Comn.Discovery

  describe "all/0" do
    test "returns all Comn modules" do
      modules = Discovery.all()
      assert length(modules) >= 22
      assert Comn.Repo in modules
      assert Comn.Repo.Table.ETS in modules
      assert Comn.Events.NATS in modules
      assert Comn.Contexts in modules
    end
  end

  describe "by_type/1" do
    test "returns behaviours" do
      behaviours = Discovery.by_type(:behaviour)
      assert Comn.Repo in behaviours
      assert Comn.Events in behaviours
      assert Comn.Secrets in behaviours
      assert Comn.Repo.File in behaviours
      assert Comn.Repo.Table in behaviours
      assert Comn.Repo.Graphs in behaviours
      assert Comn.Repo.Cmd in behaviours
      assert Comn.Infra in behaviours
    end

    test "returns implementations" do
      impls = Discovery.by_type(:implementation)
      assert Comn.Repo.Table.ETS in impls
      assert Comn.Repo.File.Local in impls
      assert Comn.Repo.File.NFS in impls
      assert Comn.Repo.File.IPFS in impls
      assert Comn.Repo.Graphs.Graph in impls
      assert Comn.Events.NATS in impls
      assert Comn.EventBus in impls
      assert Comn.Secrets.Vault in impls
    end

    test "returns facades" do
      facades = Discovery.by_type(:facade)
      assert Comn.Contexts in facades
      assert Comn.Errors in facades
    end
  end

  describe "implementations_of/1" do
    test "finds file backends" do
      impls = Discovery.implementations_of(Comn.Repo.File)
      assert Comn.Repo.File.Local in impls
      assert Comn.Repo.File.NFS in impls
      assert Comn.Repo.File.IPFS in impls
      assert length(impls) == 3
    end

    test "finds table backends" do
      impls = Discovery.implementations_of(Comn.Repo.Table)
      assert Comn.Repo.Table.ETS in impls
    end

    test "finds graph backends" do
      impls = Discovery.implementations_of(Comn.Repo.Graphs)
      assert Comn.Repo.Graphs.Graph in impls
    end

    test "finds secrets backends" do
      impls = Discovery.implementations_of(Comn.Secrets)
      assert Comn.Secrets.Vault in impls
    end

    test "repo implementations include sub-behaviours" do
      impls = Discovery.implementations_of(Comn.Repo)
      assert Comn.Repo.Table in impls
      assert Comn.Repo.Table.ETS in impls
      assert Comn.Repo.File in impls
      assert Comn.Repo.File.Local in impls
    end

    test "returns empty list for unknown behaviour" do
      assert Discovery.implementations_of(String) == []
    end
  end

  describe "lookup/1" do
    test "returns metadata for a known module" do
      meta = Discovery.lookup(Comn.Repo.Table.ETS)
      assert meta.module == Comn.Repo.Table.ETS
      assert meta.type == :implementation
      assert is_binary(meta.look)
      assert is_map(meta.recon)
      assert is_map(meta.choices)
    end

    test "returns nil for unknown module" do
      assert is_nil(Discovery.lookup(String))
    end
  end
end
