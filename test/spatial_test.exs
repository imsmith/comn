defmodule Comn.SpatialTest do
  @moduledoc """
  Acceptance test specifications for spatial-native Comn functionality.

  These tests specify the expected behaviour across all four phases
  of the spatial-native design. All tests are tagged by phase and
  excluded until the corresponding modules exist.

  Phase 1: Structured Locators (Comn.Zone + ContextStruct update)
  Phase 2: Spatial Verbs on Repo (enter/exit/discover)
  Phase 3: Presence (announce/who)
  Phase 4: Navigation (spatial traverse + context update)

  To run a specific phase:
    mix test --include phase1
    mix test --include phase2
  """

  use ExUnit.Case, async: true

  # ==========================================================================
  # Phase 1: Comn.Zone — Structured Locators
  # ==========================================================================

  describe "Comn.Zone struct" do
    @tag :phase1
    test "has realm, region, and locale fields" do
      zone = struct!(Comn.Zone)
      assert Map.has_key?(zone, :realm)
      assert Map.has_key?(zone, :region)
      assert Map.has_key?(zone, :locale)
    end

    @tag :phase1
    test "local/0 returns a zone with realm :local" do
      zone = Comn.Zone.local()
      assert zone.realm == :local
      assert zone.region == nil
      assert zone.locale == nil
    end

    @tag :phase1
    test "new/1 accepts keyword opts" do
      zone = Comn.Zone.new(realm: :mesh, region: "home", locale: "kitchen")
      assert zone.realm == :mesh
      assert zone.region == "home"
      assert zone.locale == "kitchen"
    end

    @tag :phase1
    test "parse/1 parses dot-delimited string: realm.region.locale" do
      assert {:ok, zone} = Comn.Zone.parse("mesh.home.kitchen")
      assert zone.realm == :mesh
      assert zone.region == "home"
      assert zone.locale == "kitchen"
    end

    @tag :phase1
    test "parse/1 handles realm-only string" do
      assert {:ok, zone} = Comn.Zone.parse("local")
      assert zone.realm == :local
      assert zone.region == nil
      assert zone.locale == nil
    end

    @tag :phase1
    test "parse/1 handles realm.region without locale" do
      assert {:ok, zone} = Comn.Zone.parse("cluster.us-east")
      assert zone.realm == :cluster
      assert zone.region == "us-east"
      assert zone.locale == nil
    end

    @tag :phase1
    test "parse/1 returns error for empty string" do
      assert {:error, _} = Comn.Zone.parse("")
    end

    @tag :phase1
    test "to_string/1 round-trips with parse" do
      zone = Comn.Zone.new(realm: :mesh, region: "home", locale: "kitchen")
      str = Comn.Zone.to_string(zone)
      assert {:ok, ^zone} = Comn.Zone.parse(str)
    end

    @tag :phase1
    test "to_string/1 for local zone returns 'local'" do
      assert "local" = Comn.Zone.to_string(Comn.Zone.local())
    end
  end

  describe "Comn.Zone implements Comn behaviour" do
    @tag :phase1
    test "look/0 returns a non-empty string" do
      assert is_binary(Comn.Zone.look())
      assert String.length(Comn.Zone.look()) > 0
    end

    @tag :phase1
    test "recon/0 returns a map with :type" do
      recon = Comn.Zone.recon()
      assert is_map(recon)
    end

    @tag :phase1
    test "choices/0 lists available realms" do
      choices = Comn.Zone.choices()
      assert Map.has_key?(choices, :realms)
    end

    @tag :phase1
    test "act/1 can parse a zone string" do
      assert {:ok, zone} = Comn.Zone.act(%{action: :parse, input: "local"})
      assert zone.realm == :local
    end
  end

  # ==========================================================================
  # Phase 1: ContextStruct — Zone-Aware
  # ==========================================================================

  describe "ContextStruct zone field accepts Comn.Zone" do
    @tag :phase1
    test "new/1 accepts a Comn.Zone struct as zone" do
      zone = Comn.Zone.local()
      ctx = Comn.Contexts.ContextStruct.new(%{zone: zone})
      assert ctx.zone.realm == :local
    end

    @tag :phase1
    test "new/0 defaults zone to Comn.Zone.local()" do
      ctx = Comn.Contexts.ContextStruct.new()
      assert ctx.zone.realm == :local
    end

    @tag :phase1
    test "string zone is auto-parsed for backwards compatibility" do
      ctx = Comn.Contexts.ContextStruct.new(%{zone: "mesh.home.kitchen"})
      assert ctx.zone.realm == :mesh
      assert ctx.zone.region == "home"
      assert ctx.zone.locale == "kitchen"
    end
  end

  describe "Contexts process-scoped zone management" do
    @tag :phase1
    test "zone propagates through process dictionary" do
      zone = Comn.Zone.new(realm: :cluster, region: "us-east")
      Comn.Contexts.new(%{zone: zone})
      fetched = Comn.Contexts.fetch(:zone)
      assert fetched.realm == :cluster
      assert fetched.region == "us-east"
    end

    @tag :phase1
    test "with_context/2 swaps zone and restores it" do
      outer = Comn.Zone.local()
      inner = Comn.Zone.new(realm: :mesh, region: "home")

      Comn.Contexts.new(%{zone: outer})

      Comn.Contexts.with_context(%{zone: inner}, fn ->
        assert Comn.Contexts.fetch(:zone).realm == :mesh
      end)

      assert Comn.Contexts.fetch(:zone).realm == :local
    end
  end

  # ==========================================================================
  # Phase 1: EventStruct — Topic as Spatial Address
  # ==========================================================================

  describe "EventStruct topic spatial addressing" do
    @tag :phase1
    test "flat topic string still works unchanged" do
      event = Comn.Events.EventStruct.new(:test, "media.playback.started", %{})
      assert event.topic == "media.playback.started"
    end
  end

  # ==========================================================================
  # Phase 2: Spatial Verbs on Repo
  # ==========================================================================

  describe "Comn.Repo spatial optional callbacks" do
    @tag :phase2
    test "enter/2, exit/2, discover/2 are optional callbacks" do
      optional = Comn.Repo.behaviour_info(:optional_callbacks)
      assert {:enter, 2} in optional
      assert {:exit, 2} in optional
      assert {:discover, 2} in optional
    end
  end

  describe "Graphs.Graph spatial verbs" do
    @tag :phase2
    test "enter/2 sets traversal position" do
      {:ok, gs} = Comn.Repo.Graphs.Graph.create()
      {:ok, gs} = Comn.Repo.Graphs.Graph.link(gs, :room_a, :room_b)
      zone = Comn.Zone.new(realm: :local, locale: "room_a")
      assert {:ok, _context} = Comn.Repo.Graphs.Graph.enter(gs, zone)
    end

    @tag :phase2
    test "discover/2 returns adjacent nodes" do
      {:ok, gs} = Comn.Repo.Graphs.Graph.create()
      {:ok, gs} = Comn.Repo.Graphs.Graph.link(gs, :room_a, :room_b)
      {:ok, gs} = Comn.Repo.Graphs.Graph.link(gs, :room_a, :room_c)
      zone = Comn.Zone.new(realm: :local, locale: "room_a")
      assert {:ok, discovered} = Comn.Repo.Graphs.Graph.discover(gs, zone)
      assert length(discovered) == 2
    end

    @tag :phase2
    test "exit/2 clears traversal position" do
      {:ok, gs} = Comn.Repo.Graphs.Graph.create()
      {:ok, gs} = Comn.Repo.Graphs.Graph.link(gs, :room_a, :room_b)
      zone = Comn.Zone.new(realm: :local, locale: "room_a")
      {:ok, _} = Comn.Repo.Graphs.Graph.enter(gs, zone)
      assert :ok = Comn.Repo.Graphs.Graph.exit(gs, zone)
    end

    @tag :phase2
    test "enter nonexistent zone returns error" do
      {:ok, gs} = Comn.Repo.Graphs.Graph.create()
      zone = Comn.Zone.new(realm: :local, locale: "nowhere")
      assert {:error, _} = Comn.Repo.Graphs.Graph.enter(gs, zone)
    end
  end

  describe "non-spatial repos don't need spatial verbs" do
    @tag :phase2
    test "ETS does not export enter/2" do
      refute function_exported?(Comn.Repo.Table.ETS, :enter, 2)
    end

    @tag :phase2
    test "ETS does not export discover/2" do
      refute function_exported?(Comn.Repo.Table.ETS, :discover, 2)
    end
  end

  # ==========================================================================
  # Phase 3: Presence
  # ==========================================================================

  describe "Comn.Presence behaviour" do
    @tag :phase3
    test "defines announce/3 and who/1" do
      callbacks = Comn.Presence.behaviour_info(:callbacks)
      assert {:announce, 3} in callbacks
      assert {:who, 1} in callbacks
    end
  end

  describe "Comn.Presence implements Comn behaviour" do
    @tag :phase3
    test "look/recon/choices return expected types" do
      assert is_binary(Comn.Presence.look())
      recon = Comn.Presence.recon()
      assert is_map(recon)
      assert Map.has_key?(recon, :states)
      assert is_map(Comn.Presence.choices())
    end
  end

  describe "Comn.Presence local usage" do
    @tag :phase3
    test "announce and who round-trip" do
      zone = Comn.Zone.new(realm: :local, locale: "lobby")
      :ok = Comn.Presence.announce(zone, "actor-1", :here)
      {:ok, actors} = Comn.Presence.who(zone)
      assert {"actor-1", :here} in actors
    end

    @tag :phase3
    test "announce :gone removes actor" do
      zone = Comn.Zone.new(realm: :local, locale: "lobby-gone")
      :ok = Comn.Presence.announce(zone, "actor-x", :here)
      :ok = Comn.Presence.announce(zone, "actor-x", :gone)
      {:ok, actors} = Comn.Presence.who(zone)
      refute Enum.any?(actors, fn {name, _} -> name == "actor-x" end)
    end

    @tag :phase3
    test "who/1 on empty zone returns []" do
      zone = Comn.Zone.new(realm: :local, locale: "empty")
      assert {:ok, []} = Comn.Presence.who(zone)
    end

    @tag :phase3
    test "multiple actors in same zone" do
      zone = Comn.Zone.new(realm: :local, locale: "crowded")
      :ok = Comn.Presence.announce(zone, "a", :here)
      :ok = Comn.Presence.announce(zone, "b", :busy)
      {:ok, actors} = Comn.Presence.who(zone)
      assert length(actors) == 2
    end
  end

  # ==========================================================================
  # Phase 4: Navigation (Spatial Traverse)
  # ==========================================================================

  describe "spatial traverse" do
    @tag :phase4
    test "traverse/4 returns destination zone and path" do
      {:ok, gs} = Comn.Repo.Graphs.Graph.create()
      {:ok, gs} = Comn.Repo.Graphs.Graph.link(gs, :room_a, :hallway)
      {:ok, gs} = Comn.Repo.Graphs.Graph.link(gs, :hallway, :room_b)

      from = Comn.Zone.new(realm: :local, locale: "room_a")
      {:ok, dest, path} = Comn.Repo.Graphs.Graph.traverse(gs, from, :room_b, [])
      assert dest.locale in ["room_b", :room_b]
      assert length(path) >= 2
    end

    @tag :phase4
    test "traverse updates process context zone" do
      {:ok, gs} = Comn.Repo.Graphs.Graph.create()
      {:ok, gs} = Comn.Repo.Graphs.Graph.link(gs, :room_a, :room_b)

      from = Comn.Zone.new(realm: :local, locale: "room_a")
      Comn.Contexts.new(%{zone: from})

      {:ok, dest, _path} = Comn.Repo.Graphs.Graph.traverse(gs, from, :room_b, [])
      assert Comn.Contexts.fetch(:zone) == dest
    end

    @tag :phase4
    test "traverse to unreachable node returns error" do
      {:ok, gs} = Comn.Repo.Graphs.Graph.create()
      {:ok, gs} = Comn.Repo.Graphs.Graph.link(gs, :room_a, :room_b)
      {:ok, gs} = Comn.Repo.Graphs.Graph.set(gs, vertex: :island)

      from = Comn.Zone.new(realm: :local, locale: "room_a")
      assert {:error, _} = Comn.Repo.Graphs.Graph.traverse(gs, from, :island, [])
    end
  end

  # ==========================================================================
  # Backwards Compatibility
  # ==========================================================================

  describe "backwards compatibility" do
    @tag :phase1
    test "existing Repo callbacks unchanged" do
      callbacks = Comn.Repo.behaviour_info(:callbacks)
      assert {:describe, 1} in callbacks
      assert {:get, 2} in callbacks
      assert {:set, 2} in callbacks
      assert {:delete, 2} in callbacks
      assert {:observe, 2} in callbacks
    end

    @tag :phase1
    test "existing Graph traverse/2 still works" do
      {:ok, gs} = Comn.Repo.Graphs.Graph.create()
      {:ok, gs} = Comn.Repo.Graphs.Graph.link(gs, :a, :b)
      {:ok, gs} = Comn.Repo.Graphs.Graph.link(gs, :b, :c)
      assert {:ok, [:a, :b, :c]} = Comn.Repo.Graphs.Graph.traverse(gs, type: :shortest_path, from: :a, to: :c)
    end

    @tag :phase2
    test "non-spatial repos still work normally" do
      table = :"compat_#{:erlang.unique_integer([:positive])}"
      {:ok, _} = Comn.Repo.Table.ETS.create(table)
      :ok = Comn.Repo.Table.ETS.set(table, key: "k", value: "v")
      assert {:ok, "v"} = Comn.Repo.Table.ETS.get(table, key: "k")
      Comn.Repo.Table.ETS.drop(table)
    end
  end
end
