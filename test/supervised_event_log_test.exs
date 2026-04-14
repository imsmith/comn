defmodule Comn.SupervisedEventLogTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias Comn.EventLog
  alias Comn.Events.EventStruct

  setup do
    EventLog.clear()
    :ok
  end

  describe "EventLog under supervision" do
    test "is already running from Comn.Supervisor" do
      assert Process.whereis(Comn.EventLog) != nil
    end

    test "record/all round-trip through supervised process" do
      event = EventStruct.new(:test, "supervised.test", %{n: 1})
      :ok = EventLog.record(event)

      events = EventLog.all()
      assert length(events) == 1
      assert hd(events).topic == "supervised.test"
    end

    test "survives clear and reuse" do
      EventLog.record(EventStruct.new(:test, "t", %{}))
      assert length(EventLog.all()) == 1

      EventLog.clear()
      assert EventLog.all() == []

      EventLog.record(EventStruct.new(:test, "t2", %{}))
      assert length(EventLog.all()) == 1
    end

    test "record rejects invalid input via protocol" do
      assert {:error, :missing_keys} = EventLog.record(%{bad: "input"})
      assert EventLog.all() == []
    end

    test "for_topic and for_type work on supervised instance" do
      EventLog.record(EventStruct.new(:info, "a.topic", %{}))
      EventLog.record(EventStruct.new(:error, "b.topic", %{}))
      EventLog.record(EventStruct.new(:info, "a.topic", %{}))

      assert length(EventLog.for_topic("a.topic")) == 2
      assert length(EventLog.for_type(:error)) == 1
    end
  end
end
