defimpl Comn.Error, for: Map do
  def to_error(%{
        "reason" => reason,
        "field" => field,
        "message" => message,
        "suggestion" => suggestion
      }) do
    {:ok, Comn.Errors.ErrorStruct.new(reason, field, message, suggestion)}
  end

  def to_error(%{reason: reason, field: field, message: message, suggestion: suggestion}) do
    {:ok, Comn.Errors.ErrorStruct.new(reason, field, message, suggestion)}
  end

  def to_error(_invalid) do
    {:error, Comn.Errors.Registry.error!("errors/missing_keys")}
  end
end
