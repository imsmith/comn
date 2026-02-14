defmodule Comn.Contexts do
  @moduledoc """
  Process-scoped context management using ContextStruct.

  Stores context in the process dictionary so it's available
  throughout a request/operation lifecycle without explicit passing.
  """

  alias Comn.Contexts.ContextStruct

  @key :comn_context

  @doc "Sets the current process context."
  @spec set(ContextStruct.t()) :: :ok
  def set(%ContextStruct{} = ctx) do
    Process.put(@key, ctx)
    :ok
  end

  @doc "Gets the current process context, or nil if none set."
  @spec get() :: ContextStruct.t() | nil
  def get do
    Process.get(@key)
  end

  @doc "Creates a new context and sets it on the current process."
  @spec new() :: ContextStruct.t()
  def new do
    ctx = ContextStruct.new()
    set(ctx)
    ctx
  end

  @doc "Creates a new context from fields and sets it on the current process."
  @spec new(map() | keyword()) :: ContextStruct.t()
  def new(fields) do
    ctx = ContextStruct.new(fields)
    set(ctx)
    ctx
  end

  @doc "Puts a value into the current process context."
  @spec put(atom(), term()) :: :ok
  def put(key, value) do
    ctx = get() || ContextStruct.new()
    set(ContextStruct.put(ctx, key, value))
  end

  @doc "Gets a value from the current process context."
  @spec fetch(atom()) :: term()
  def fetch(key) do
    case get() do
      nil -> nil
      ctx -> ContextStruct.get(ctx, key)
    end
  end

  @doc """
  Runs a function with the given context set, restoring the previous context after.
  """
  @spec with_context(ContextStruct.t() | map() | keyword(), (-> result)) :: result when result: any()
  def with_context(%ContextStruct{} = ctx, fun) do
    old = get()
    set(ctx)
    try do
      fun.()
    after
      case old do
        nil -> Process.delete(@key)
        prev -> set(prev)
      end
    end
  end

  def with_context(fields, fun) when is_map(fields) or is_list(fields) do
    with_context(ContextStruct.new(fields), fun)
  end
end
