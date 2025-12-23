defprotocol Comn.Context do
  @doc "Converts various data types into a ContextStruct"
  def to_context(term)
end
