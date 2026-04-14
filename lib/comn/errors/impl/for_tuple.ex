defimpl Comn.Error, for: Tuple do
  def to_error({reason, field, message, suggestion}) do
    {:ok, Comn.Errors.ErrorStruct.new(reason, field, message, suggestion)}
  end

  def to_error(_invalid) do
    {:error, :invalid_tuple}
  end
end
