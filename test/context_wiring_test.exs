defmodule Comn.ContextWiringTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias Comn.Contexts
  alias Comn.Errors
  alias Comn.Errors.ErrorStruct
  alias Comn.Events.EventStruct

  describe "EventStruct auto-enrichment" do
    test "new/3 pulls request_id and correlation_id from ambient context" do
      Contexts.new(request_id: "req-100", correlation_id: "corr-200")

      event = EventStruct.new(:test, "order.placed", %{id: 1})

      assert event.request_id == "req-100"
      assert event.correlation_id == "corr-200"
      assert is_binary(event.id)
      assert event.metadata == %{}
    end

    test "new/3 works without ambient context" do
      Process.delete(:comn_context)

      event = EventStruct.new(:test, "order.placed", %{})

      assert is_nil(event.request_id)
      assert is_nil(event.correlation_id)
      assert is_binary(event.id)
    end

    test "each event gets a unique id" do
      ids =
        for _ <- 1..10 do
          EventStruct.new(:test, "t", %{}).id
        end

      assert length(Enum.uniq(ids)) == 10
    end
  end

  describe "Errors.wrap/1 auto-enrichment" do
    test "wrap/1 pulls context fields" do
      Contexts.new(
        request_id: "req-300",
        trace_id: "trace-400",
        correlation_id: "corr-500"
      )

      {:ok, error} = Errors.wrap("something broke")

      assert %ErrorStruct{} = error
      assert error.request_id == "req-300"
      assert error.trace_id == "trace-400"
      assert error.correlation_id == "corr-500"
    end

    test "wrap/1 works without ambient context" do
      Process.delete(:comn_context)

      {:ok, error} = Errors.wrap("no context here")

      assert %ErrorStruct{} = error
      assert is_nil(error.request_id)
      assert is_nil(error.trace_id)
      assert is_nil(error.correlation_id)
    end
  end

  describe "Errors.new/4 auto-enrichment" do
    test "new/2 pulls context fields" do
      Contexts.new(request_id: "req-600", trace_id: "trace-700")

      error = Errors.new(:validation, "bad input")

      assert error.request_id == "req-600"
      assert error.trace_id == "trace-700"
    end

    test "new/4 pulls context fields" do
      Contexts.new(correlation_id: "corr-800")

      error = Errors.new(:network, "timeout", :endpoint, "check DNS")

      assert error.correlation_id == "corr-800"
      assert error.field == :endpoint
      assert error.suggestion == "check DNS"
    end
  end

  describe "context isolation between processes" do
    test "events in different processes get different context" do
      Contexts.new(request_id: "parent-req")

      task =
        Task.async(fn ->
          Contexts.new(request_id: "child-req")
          EventStruct.new(:test, "t", %{})
        end)

      parent_event = EventStruct.new(:test, "t", %{})
      child_event = Task.await(task)

      assert parent_event.request_id == "parent-req"
      assert child_event.request_id == "child-req"
    end
  end
end
