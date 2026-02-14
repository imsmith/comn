defmodule Comn.Contexts.ContextStruct do
  @moduledoc "Concrete context struct for passing contextual information."

  defstruct [
    :request_id,
    :trace_id,
    :correlation_id,
    :user_id,
    :actor,
    :env,
    :zone,
    :parent_event_id,
    metadata: %{}
  ]

  @type t :: %__MODULE__{
          request_id: String.t() | nil,
          trace_id: String.t() | nil,
          correlation_id: String.t() | nil,
          user_id: String.t() | nil,
          actor: String.t() | nil,
          env: String.t() | nil,
          zone: String.t() | nil,
          parent_event_id: String.t() | nil,
          metadata: map()
        }

  @doc "Creates a new empty context."
  def new do
    %__MODULE__{}
  end

  @doc "Creates a new context from a keyword list or map of fields."
  def new(%__MODULE__{} = ctx), do: ctx

  def new(fields) when is_map(fields) do
    struct(__MODULE__, Map.to_list(fields))
  end

  def new(fields) when is_list(fields) do
    struct(__MODULE__, fields)
  end

  @doc "Returns the context as a plain map, dropping nil values."
  def to_map(%__MODULE__{} = ctx) do
    ctx
    |> Map.from_struct()
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  @doc "Puts a value into the context."
  def put(%__MODULE__{} = ctx, key, value) when is_atom(key) do
    if Map.has_key?(ctx, key) do
      Map.put(ctx, key, value)
    else
      %{ctx | metadata: Map.put(ctx.metadata, key, value)}
    end
  end

  @doc "Gets a value from the context."
  def get(%__MODULE__{} = ctx, key) when is_atom(key) do
    if Map.has_key?(ctx, key) do
      Map.get(ctx, key)
    else
      Map.get(ctx.metadata, key)
    end
  end
end
