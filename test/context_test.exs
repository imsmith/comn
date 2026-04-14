defmodule Comn.ContextsTest do
  use ExUnit.Case, async: true

  alias Comn.Contexts
  alias Comn.Contexts.ContextStruct
  alias Comn.Context

  describe "ContextStruct" do
    test "new/0 creates an empty context" do
      ctx = ContextStruct.new()
      assert %ContextStruct{} = ctx
      assert is_nil(ctx.request_id)
      assert ctx.metadata == %{}
    end

    test "new/1 creates a context from a map" do
      ctx = ContextStruct.new(%{request_id: "req-123", user_id: "user-1"})
      assert ctx.request_id == "req-123"
      assert ctx.user_id == "user-1"
    end

    test "new/1 creates a context from a keyword list" do
      ctx = ContextStruct.new(request_id: "req-456", env: "test")
      assert ctx.request_id == "req-456"
      assert ctx.env == "test"
    end

    test "put/3 sets a known field" do
      ctx = ContextStruct.new() |> ContextStruct.put(:request_id, "req-789")
      assert ctx.request_id == "req-789"
    end

    test "put/3 sets an unknown field into metadata" do
      ctx = ContextStruct.new() |> ContextStruct.put(:custom_key, "custom_val")
      assert ctx.metadata == %{custom_key: "custom_val"}
    end

    test "get/2 reads a known field" do
      ctx = ContextStruct.new(%{trace_id: "trace-1"})
      assert ContextStruct.get(ctx, :trace_id) == "trace-1"
    end

    test "get/2 reads from metadata for unknown fields" do
      ctx = ContextStruct.new() |> ContextStruct.put(:custom, "val")
      assert ContextStruct.get(ctx, :custom) == "val"
    end

    test "to_map/1 drops nil values" do
      ctx = ContextStruct.new(%{request_id: "req-1"})
      map = ContextStruct.to_map(ctx)
      assert map.request_id == "req-1"
      refute Map.has_key?(map, :trace_id)
      assert Map.has_key?(map, :metadata)
    end
  end

  describe "Comn.Context protocol" do
    test "converts a map to ContextStruct" do
      {:ok, ctx} = Context.to_context(%{request_id: "req-proto"})
      assert %ContextStruct{} = ctx
      assert ctx.request_id == "req-proto"
    end

    test "converts a keyword list to ContextStruct" do
      {:ok, ctx} = Context.to_context(user_id: "user-proto")
      assert %ContextStruct{} = ctx
      assert ctx.user_id == "user-proto"
    end

    test "passes through an existing ContextStruct" do
      original = ContextStruct.new(%{env: "prod"})
      assert {:ok, ^original} = Context.to_context(original)
    end
  end

  describe "Comn.Contexts process-scoped" do
    test "new/0 creates and sets context on process" do
      ctx = Contexts.new()
      assert %ContextStruct{} = ctx
      assert Contexts.get() == ctx
    end

    test "new/1 creates context from fields" do
      ctx = Contexts.new(%{request_id: "req-proc"})
      assert ctx.request_id == "req-proc"
      assert Contexts.get() == ctx
    end

    test "put/2 and fetch/1 work on process context" do
      Contexts.new()
      Contexts.put(:request_id, "req-put")
      assert Contexts.fetch(:request_id) == "req-put"
    end

    test "with_context/2 restores previous context" do
      Contexts.new(%{request_id: "outer"})

      Contexts.with_context(%{request_id: "inner"}, fn ->
        assert Contexts.fetch(:request_id) == "inner"
      end)

      assert Contexts.fetch(:request_id) == "outer"
    end

    test "with_context/2 restores nil when no previous context" do
      Process.delete(:comn_context)

      Contexts.with_context(%{request_id: "temp"}, fn ->
        assert Contexts.fetch(:request_id) == "temp"
      end)

      assert Contexts.get() == nil
    end
  end
end
