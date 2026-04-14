defprotocol Comn.Error do
  @moduledoc """
  Protocol for converting arbitrary terms into `Comn.Errors.ErrorStruct`.

  Implement this protocol for any type that should be convertible to a
  structured error. Built-in implementations handle maps, tuples, binaries,
  atoms, and `ErrorStruct` passthrough.

  ## Examples

      iex> {:ok, err} = Comn.Error.to_error("something broke")
      iex> err.message
      "something broke"

      iex> {:ok, err} = Comn.Error.to_error(%{reason: "auth", field: "token", message: "expired", suggestion: "refresh"})
      iex> err.reason
      "auth"
  """

  @doc """
  Converts a term into a `Comn.Errors.ErrorStruct`.

  Returns `{:ok, error_struct}` or `{:error, reason}`.
  """
  @spec to_error(t) :: {:ok, Comn.Errors.ErrorStruct.t()} | {:error, term()}
  def to_error(term)
end
