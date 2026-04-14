defprotocol Comn.Context do
  @moduledoc """
  Protocol for converting arbitrary terms into `Comn.Contexts.ContextStruct`.

  Implement this protocol for any type that should be convertible to a
  process context. Built-in implementations handle maps, keyword lists,
  and `ContextStruct` passthrough.

  ## Examples

      iex> {:ok, ctx} = Comn.Context.to_context(%{request_id: "req-1"})
      iex> ctx.request_id
      "req-1"

      iex> {:ok, ctx} = Comn.Context.to_context(user_id: "user-42")
      iex> ctx.user_id
      "user-42"
  """

  @doc """
  Converts a term into a `Comn.Contexts.ContextStruct`.

  Returns `{:ok, context_struct}` or `{:error, reason}`.
  """
  @spec to_context(t) :: {:ok, Comn.Contexts.ContextStruct.t()} | {:error, term()}
  def to_context(term)
end

defimpl Comn.Context, for: Map do
  def to_context(map) do
    {:ok, Comn.Contexts.ContextStruct.new(map)}
  end
end

defimpl Comn.Context, for: List do
  def to_context(keyword) do
    {:ok, Comn.Contexts.ContextStruct.new(keyword)}
  end
end

defimpl Comn.Context, for: Comn.Contexts.ContextStruct do
  def to_context(ctx), do: {:ok, ctx}
end
