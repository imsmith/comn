defprotocol Comn.Secret do
  @moduledoc """
  Protocol for converting Elixir terms to/from binary blobs for encryption.

  Any type that implements this protocol can be locked/unlocked using the
  `Comn.Secrets` behaviour.

  ## Examples

      defimpl Comn.Secret, for: Map do
        def to_blob(map), do: {:ok, :erlang.term_to_binary(map)}
        def from_blob(blob), do: {:ok, :erlang.binary_to_term(blob, [:safe])}
      end
  """

  @doc """
  Convert a term to a binary blob for encryption.

  Returns `{:ok, binary}` or `{:error, reason}`.
  """
  @spec to_blob(t) :: {:ok, binary()} | {:error, term()}
  def to_blob(term)

  @doc """
  Convert a binary blob back to the original term type.

  Returns `{:ok, term}` or `{:error, reason}`.
  """
  @spec from_blob(binary()) :: {:ok, t} | {:error, term()}
  def from_blob(blob)
end
