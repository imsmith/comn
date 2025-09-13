defmodule Events.RegistryTest do
  use ExUnit.Case, async: true
  doctest Events.Registry


  describe "subscribe/1" do
    test "subscribes to a topic" do
      assert :ok = Events.Registry.subscribe("test_topic")
    end

    test "allows multiple subscriptions to the same topic" do
      assert :ok = Events.Registry.subscribe("test_topic")
      assert :ok = Events.Registry.subscribe("test_topic")
    end

    test "handles subscription errors" do
      assert {:error, _reason} = Events.Registry.subscribe(nil)
    end


  end

  test "greets the world" do
    assert Events.Registry.hello() == :world
  end
end
