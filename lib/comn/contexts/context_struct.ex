defmodule Comn.Contexts.ContextStruct do
  @moduledoc "Concrete context struct for passing contextual information."

  alias Comn.Zone

  @enforce_keys []
  defstruct [
    :request_id,
    :trace_id,
    :correlation_id,
    :user_id,
    :actor,
    :env,
    :parent_event_id,
    zone: nil,
    metadata: %{}
  ]

  @type t :: %__MODULE__{
          request_id: String.t() | nil,
          trace_id: String.t() | nil,
          correlation_id: String.t() | nil,
          user_id: String.t() | nil,
          actor: String.t() | nil,
          env: String.t() | nil,
          zone: Zone.t() | nil,
          parent_event_id: String.t() | nil,
          metadata: map()
        }

  @doc "Creates a new empty context with the local zone."
  @spec new() :: t()
  def new do
    %__MODULE__{zone: Zone.local()}
  end

  @doc """
  Creates a new context from fields.

  A `:zone` field given as a string is auto-parsed via `Comn.Zone.parse/1`
  for backwards compatibility with the old string-typed zone. If `:zone` is
  not supplied, defaults to `Comn.Zone.local()`.
  """
  @spec new(t() | map() | keyword()) :: t()
  def new(%__MODULE__{} = ctx), do: ctx

  def new(fields) when is_map(fields) do
    fields |> Map.to_list() |> from_list()
  end

  def new(fields) when is_list(fields) do
    from_list(fields)
  end

  defp from_list(fields) do
    fields = Keyword.update(fields, :zone, Zone.local(), &normalize_zone/1)
    struct!(__MODULE__, fields)
  end

  defp normalize_zone(%Zone{} = z), do: z
  defp normalize_zone(str) when is_binary(str) do
    case Zone.parse(str) do
      {:ok, z} -> z
      {:error, _} -> Zone.local()
    end
  end
  defp normalize_zone(nil), do: Zone.local()

  @doc "Returns the context as a plain map, dropping nil values."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = ctx) do
    ctx
    |> Map.from_struct()
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  @doc "Puts a value into the context."
  @spec put(t(), atom(), term()) :: t()
  def put(%__MODULE__{} = ctx, key, value) when is_atom(key) do
    if Map.has_key?(ctx, key) do
      Map.put(ctx, key, value)
    else
      %{ctx | metadata: Map.put(ctx.metadata, key, value)}
    end
  end

  @doc "Gets a value from the context."
  @spec get(t(), atom()) :: term()
  def get(%__MODULE__{} = ctx, key) when is_atom(key) do
    if Map.has_key?(ctx, key) do
      Map.get(ctx, key)
    else
      Map.get(ctx.metadata, key)
    end
  end
end
