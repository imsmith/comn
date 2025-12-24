defprotocol Comn.Secret do
  @moduledoc """
  Protocol for converting Elixir terms to/from binary blobs for encryption.

  Any type that implements this protocol can be locked/unlocked using the
  Comn.Secrets behavior.

  ## Example

      defimpl Comn.Secret, for: Map do
        def to_blob(map) do
          :erlang.term_to_binary(map)
        end

        def from_blob(blob) do
          :erlang.binary_to_term(blob)
        end
      end
  """

  @doc """
  Convert a term to a binary blob for encryption.
  """
  @spec to_blob(t) :: binary()
  def to_blob(term)

  @doc """
  Convert a binary blob back to the original term type.
  """
  @spec from_blob(binary()) :: t
  def from_blob(blob)
end
