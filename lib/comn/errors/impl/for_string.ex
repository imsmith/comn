defimpl String.Chars, for: Comn.Errors.ErrorStruct do
  def to_string(%{reason: r, message: m}) do
    "[#{r}] #{m}"
  end
end

defimpl Comn.Error, for: BitString do
  def to_error(message) when is_binary(message) do
    {:ok, Comn.Errors.ErrorStruct.new("unknown", nil, message, nil)}
  end
end

defimpl Comn.Error, for: Atom do
  def to_error(reason) do
    {:ok, Comn.Errors.ErrorStruct.new(Atom.to_string(reason), nil, Atom.to_string(reason), nil)}
  end
end
