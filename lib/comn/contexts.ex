defmodule Comn.Contexts do
  @moduledoc """
  Process-scoped context management using the process dictionary.

  Stores a `Comn.Contexts.ContextStruct` in the calling process so request
  metadata (request IDs, trace IDs, user info) is available throughout an
  operation lifecycle without explicit passing.

  Also implements `@behaviour Comn` for uniform introspection.

  ## Examples

      iex> ctx = Comn.Contexts.new(request_id: "req-1")
      iex> ctx.request_id
      "req-1"

      iex> Comn.Contexts.fetch(:request_id)
      "req-1"

      iex> Comn.Contexts.look()
      "Contexts — process-scoped context management via process dictionary"
  """

  @behaviour Comn

  alias Comn.Contexts.ContextStruct

  # Process dictionary is intentional here — ambient context propagation is the
  # standard BEAM pattern for request-scoped metadata (see Logger metadata,
  # OpenTelemetry baggage). The alternative (explicit parameter threading) would
  # require every function in the call chain to accept and forward a context arg.
  @key :comn_context

  @doc "Sets the current process context."
  @spec set(ContextStruct.t()) :: :ok
  def set(%ContextStruct{} = ctx) do
    Process.put(@key, ctx) # intentional: ambient context, same pattern as Logger metadata
    :ok
  end

  @doc "Gets the current process context, or nil if none set."
  @spec get() :: ContextStruct.t() | nil
  def get do
    Process.get(@key) # intentional: ambient context, same pattern as Logger metadata
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
        nil -> Process.delete(@key) # intentional: restore clean state
        prev -> set(prev)
      end
    end
  end

  def with_context(fields, fun) when is_map(fields) or is_list(fields) do
    with_context(ContextStruct.new(fields), fun)
  end

  # Comn callbacks

  @impl Comn
  def look, do: "Contexts — process-scoped context management via process dictionary"

  @impl Comn
  def recon do
    %{
      storage: :process_dictionary,
      struct: Comn.Contexts.ContextStruct,
      fields: [:request_id, :trace_id, :correlation_id, :user_id, :actor, :env, :zone, :parent_event_id, :metadata],
      type: :facade
    }
  end

  @impl Comn
  def choices do
    %{actions: ["get", "set", "new", "put", "fetch", "with_context"]}
  end

  @impl Comn
  def act(%{action: :new, fields: fields}), do: {:ok, new(fields)}
  def act(%{action: :new}), do: {:ok, new()}
  def act(%{action: :get}), do: {:ok, get()}
  def act(%{action: :set, context: ctx}), do: {:ok, set(ctx)}
  def act(_input), do: {:error, :unknown_action}
end
