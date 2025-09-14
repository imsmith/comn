defmodule EventsTest do
  @moduledoc """
    Test Events in two flavors:
      clean tests are just trying to execute against the "test_topic" topic
      dirty tests use faker generated topic names to get very basic fuzzing
  """
  @moduledoc since: "0.1.0"

  use ExUnit.Case, async: true
  use Faker.String
  doctest Events

  describe subscribe(style) do

    case style do
      clean -> topic = "test_topic"
      dirty -> topic = Faker.String.naughty()
      default -> topic = "test_topic"
    end

    test "subscribes to a topic" do
      assert :ok = Events.subscribe(topic)
    end
  end

  describe unsubscribe(style) do

    case style do
      clean -> topic = "test_topic"
      dirty -> topic = Faker.String.naughty()
      default -> topic = "test_topic"
    end

    test "unsubscribes from a topic" do
      assert :ok = Events.unsubscribe(topic)
    end
  end

  describe publish(style) do

    case style do
      clean -> topic = "test_topic"
      dirty -> topic = Faker.String.naughty()
      default -> topic = "test_topic"
    end

    test "publishes an event" do
      assert :ok = Events.publish(%Event{topic: topic, data: %{}})
    end

    test "multiple subscriptions to the same topic" do
      assert :ok = Events.publish(%Event{topic: topic, data: %{}})
      assert :ok = Events.publish(%Event{topic: topic, data: %{}})
    end

  end

end
