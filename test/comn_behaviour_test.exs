defmodule Comn.BehaviourTest do
  @moduledoc """
  Acceptance tests for the Comn behaviour (look/recon/choices/act)
  across all modules that declare @behaviour Comn.
  """

  use ExUnit.Case, async: true

  @all_modules [
    # Behaviours
    Comn.Repo,
    Comn.Repo.Cmd,
    Comn.Repo.Table,
    Comn.Repo.File,
    Comn.Repo.Graphs,
    Comn.Events,
    Comn.Secrets,
    Comn.Infra,
    # Implementations
    Comn.Repo.Table.ETS,
    Comn.Repo.File.Local,
    Comn.Repo.File.NFS,
    Comn.Repo.File.IPFS,
    Comn.Repo.Graphs.Graph,
    Comn.Repo.Cmd.Shell,
    Comn.Repo.Actor,
    Comn.Events.NATS,
    Comn.EventBus,
    Comn.Events.Registry,
    Comn.EventLog,
    Comn.Secrets.Local,
    Comn.Secrets.Vault,
    # Facades
    Comn.Contexts,
    Comn.Errors
  ]

  @behaviour_modules [Comn.Repo, Comn.Repo.Cmd, Comn.Repo.Table, Comn.Repo.File, Comn.Repo.Graphs, Comn.Events, Comn.Secrets, Comn.Infra]
  @placeholder_modules [Comn.Infra, Comn.Repo.Actor, Comn.Repo.Cmd.Shell]

  describe "Comn behaviour defines four callbacks" do
    test "look/0, recon/0, choices/0, act/1 are required" do
      callbacks = Comn.behaviour_info(:callbacks)
      assert {:look, 0} in callbacks
      assert {:recon, 0} in callbacks
      assert {:choices, 0} in callbacks
      assert {:act, 1} in callbacks
    end
  end

  describe "every module implements look/0" do
    for mod <- @all_modules do
      @mod mod
      test "#{inspect(mod)}.look/0 returns a non-empty string" do
        result = @mod.look()
        assert is_binary(result)
        assert String.length(result) > 0
      end
    end
  end

  describe "every module implements recon/0" do
    for mod <- @all_modules do
      @mod mod
      test "#{inspect(mod)}.recon/0 returns a map" do
        result = @mod.recon()
        assert is_map(result)
      end
    end
  end

  describe "every module implements choices/0" do
    for mod <- @all_modules do
      @mod mod
      test "#{inspect(mod)}.choices/0 returns a map" do
        result = @mod.choices()
        assert is_map(result)
      end
    end
  end

  describe "behaviour modules return :behaviour_only from act/1" do
    for mod <- (@behaviour_modules -- @placeholder_modules) do
      @mod mod
      test "#{inspect(mod)}.act/1 returns {:error, :behaviour_only}" do
        assert {:error, :behaviour_only} = @mod.act(%{})
      end
    end
  end

  describe "placeholder modules return :not_implemented from act/1" do
    for mod <- @placeholder_modules do
      @mod mod
      test "#{inspect(mod)}.act/1 returns {:error, :not_implemented}" do
        assert {:error, :not_implemented} = @mod.act(%{})
      end
    end
  end

  describe "implementation modules handle unknown actions" do
    @impl_modules [
      Comn.Repo.Table.ETS,
      Comn.Repo.File.Local,
      Comn.Repo.File.NFS,
      Comn.Repo.File.IPFS,
      Comn.Repo.Graphs.Graph,
      Comn.Events.NATS,
      Comn.EventBus,
      Comn.Events.Registry,
      Comn.EventLog,
      Comn.Secrets.Local,
      Comn.Secrets.Vault,
      Comn.Contexts,
      Comn.Errors
    ]

    for mod <- @impl_modules do
      @mod mod
      test "#{inspect(mod)}.act/1 returns {:error, :unknown_action} for bogus input" do
        assert {:error, :unknown_action} = @mod.act(%{action: :bogus_action_that_does_not_exist})
      end
    end
  end

  describe "recon/0 includes :type field" do
    for mod <- @all_modules do
      @mod mod
      test "#{inspect(mod)}.recon/0 has :type or :status key" do
        recon = @mod.recon()
        assert Map.has_key?(recon, :type) or Map.has_key?(recon, :status),
          "#{inspect(@mod)}.recon/0 should include :type or :status"
      end
    end
  end

  describe "ETS act/1 dispatches real operations" do
    setup do
      table = :"act_test_#{:erlang.unique_integer([:positive])}"
      {:ok, _} = Comn.Repo.Table.ETS.create(table)
      on_exit(fn -> Comn.Repo.Table.ETS.drop(table) end)
      %{table: table}
    end

    test "act :set and :get", %{table: table} do
      assert :ok = Comn.Repo.Table.ETS.act(%{action: :set, name: table, key: "k", value: "v"})
      assert {:ok, "v"} = Comn.Repo.Table.ETS.act(%{action: :get, name: table, key: "k"})
    end

    test "act :delete", %{table: table} do
      Comn.Repo.Table.ETS.act(%{action: :set, name: table, key: "d", value: "val"})
      assert :ok = Comn.Repo.Table.ETS.act(%{action: :delete, name: table, key: "d"})
      assert {:error, {:not_found, "d"}} = Comn.Repo.Table.ETS.act(%{action: :get, name: table, key: "d"})
    end
  end
end
