defmodule Comn.EventsTest do
  use ExUnit.Case, async: true

  alias Comn.Events.EventStruct
  alias Comn.Event
  alias Comn.EventBus
  alias Comn.EventLog

  describe "EventStruct" do
    test "new/3 creates an event with timestamp" do
      event = EventStruct.new(:test, "topic.test", %{key: "value"})
      assert event.type == :test
      assert event.topic == "topic.test"
      assert event.data == %{key: "value"}
      assert is_binary(event.timestamp)
    end

    test "new/4 creates an event with custom source" do
      event = EventStruct.new(:test, "topic.test", %{}, :my_source)
      assert event.source == :my_source
    end
  end

  describe "Comn.Event protocol" do
    test "converts a map with atom keys" do
      {:ok, event} = Event.to_event(%{type: :info, topic: "test", data: %{}})
      assert %EventStruct{} = event
      assert event.type == :info
    end

    test "converts a 3-tuple" do
      {:ok, event} = Event.to_event({:warn, "test.topic", %{msg: "hi"}})
      assert %EventStruct{} = event
      assert event.type == :warn
    end

    test "passes through an existing EventStruct" do
      original = EventStruct.new(:test, "topic", %{})
      assert {:ok, ^original} = Event.to_event(original)
    end

    test "returns error for invalid map" do
      assert {:error, :missing_keys} = Event.to_event(%{foo: "bar"})
    end

    test "returns error for invalid tuple" do
      assert {:error, :invalid_tuple} = Event.to_event({:only_one})
    end
  end

  describe "EventBus" do
    test "subscribe and broadcast" do
      EventBus.subscribe("test.bus")
      EventBus.broadcast("test.bus", %{msg: "hello"})
      assert_receive {:event, "test.bus", %{msg: "hello"}}
    end

    test "does not receive events from other topics" do
      EventBus.subscribe("topic.a")
      EventBus.broadcast("topic.b", %{msg: "hello"})
      refute_receive {:event, "topic.a", _}
    end
  end

  describe "EventLog" do
    setup do
      EventLog.clear()
      :ok
    end

    test "record and all" do
      EventLog.record(EventStruct.new(:test, "log.test", %{n: 1}))
      EventLog.record(EventStruct.new(:test, "log.test", %{n: 2}))
      events = EventLog.all()
      assert length(events) == 2
      assert hd(events).data == %{n: 1}
    end

    test "for_topic filters by topic" do
      EventLog.record(EventStruct.new(:test, "a", %{}))
      EventLog.record(EventStruct.new(:test, "b", %{}))
      assert length(EventLog.for_topic("a")) == 1
    end

    test "for_type filters by type" do
      EventLog.record(EventStruct.new(:info, "t", %{}))
      EventLog.record(EventStruct.new(:error, "t", %{}))
      assert length(EventLog.for_type(:error)) == 1
    end

    test "clear empties the log" do
      EventLog.record(EventStruct.new(:test, "t", %{}))
      EventLog.clear()
      assert EventLog.all() == []
    end
  end
end
