defmodule EventsTest do
  use ExUnit.Case, async: true
  doctest Events

  describe publish/1 do
    test "publishes an event" do
      assert :ok = Events.publish(%Event{topic: "test_topic", data: %{}})
    end

    test "multiple subscriptions to the same topic" do
      assert :ok = Events.publish(%Event{topic: "test_topic", data: %{}})
      assert :ok = Events.publish(%Event{topic: "test_topic", data: %{}})
    end

    test
  end

  describe subscribe/1 do
    test "subscribes to a topic" do
      assert :ok = Events.subscribe("test_topic")
    end
  end

  describe unsubscribe/1 do
    test "unsubscribes from a topic" do
      assert :ok = Ev    ents.unsubscribe("test_topic")
    end
  end
end
