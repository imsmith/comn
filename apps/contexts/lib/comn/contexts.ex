defmodule Comn.Contexts do
  @moduledoc """
  Behaviour defining the interface for context management.
  """

  alias Comn.Contexts.ContextStruct, as: ContextStruct

end

#  this is, i think, what I originally intended to have here, but now it needs to be refactored so that is uses ContextStruct
#
# **What you want is a lightweight, process-scoped, key-value carrier** for stuff like:
#
#- `request_id`
#- `trace_id`
#- `correlation_id`
#- `user_id`
#- `actor`
#- `env`
#- `zone`
#- `parent_event_id`
#
#
#defmodule Comn.Context do
#  def put(key, value), do: Process.put({__MODULE__, key}, value)
#  def get(key), do: Process.get({__MODULE__, key})
#  def get_all, do: Process.get_keys() |> Enum.filter_map(&match?({__MODULE__, _}, &1), &{elem(&1, 1), Process.get(&1)})
#
#  def with_context(map, fun) when is_map(map) do
#    old = Map.new(map, fn {k, _} -> {{__MODULE__, k}, Process.get({__MODULE__, k})} end)
#    Enum.each(map, fn {k, v} -> put(k, v) end)
#    try do
#      fun.()
#    after
#      Enum.each(old, fn {{_, k}, v} -> put(k, v) end)
#    end
#  end
#end
