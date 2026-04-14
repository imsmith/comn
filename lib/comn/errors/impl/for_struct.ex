defimpl Comn.Error, for: Comn.Errors.ErrorStruct do
  def to_error(error), do: {:ok, error}
end
