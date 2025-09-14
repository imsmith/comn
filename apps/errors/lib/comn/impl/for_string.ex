defimpl String.Chars, for: Comn.Errors.ErrorStruct do
  def to_string(%{reason: r, message: m}) do
    #"[#{r}] #{m}"
    Comn.Errors.ErrorStruct.new(r, nil, m, nil)
  end

  def to_error(_invalid) do
    raise ArgumentError, "Map must contain :reason, :field keys"
  end

end
