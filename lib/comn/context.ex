defprotocol Comn.Context do
  @doc "Converts various data types into a ContextStruct"
  def to_context(term)
end

defimpl Comn.Context, for: Map do
  def to_context(map) do
    Comn.Contexts.ContextStruct.new(map)
  end
end

defimpl Comn.Context, for: List do
  def to_context(keyword) do
    Comn.Contexts.ContextStruct.new(keyword)
  end
end

defimpl Comn.Context, for: Comn.Contexts.ContextStruct do
  def to_context(ctx), do: ctx
end
