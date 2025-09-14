defimpl Comn.Error, for: Tuple do
  def to_error({reason, field, message, suggestion}) do
    Comn.Errors.ErrorStruct.new(reason, field, message, suggestion)
  end

  def to_error(_invalid) do
    raise ArgumentError, "Tuple must contain reason, field, message, and suggestion elements"
  end
end
