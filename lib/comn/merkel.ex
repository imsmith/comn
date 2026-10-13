defprotocol Comn.Merkel do
  @moduledoc """
  Protocol for the canonical bytes of a term: the bytes whose hash is its
  content address in `Comn.Repo.Merkel`.

  Two terms with the same content must produce the same bytes, every time,
  on every node. The default for any term is Erlang's deterministic
  external term format; a raw binary is its own content, so file bytes
  hash as file bytes. Implement this for a type whose canonical form should
  be portable (e.g. canonical JSON) rather than BEAM-specific.

  ## Examples

      iex> Comn.Merkel.to_content("bytes")
      "bytes"

      iex> e = Comn.Events.EventStruct.new(:test, "doc", %{})
      iex> Comn.Merkel.to_content(e) == Comn.Merkel.to_content(e)
      true
  """

  @fallback_to_any true

  @doc "The canonical bytes of `term`."
  @spec to_content(t) :: binary()
  def to_content(term)
end

defimpl Comn.Merkel, for: BitString do
  def to_content(bin) when is_binary(bin), do: bin
  def to_content(bits), do: :erlang.term_to_binary(bits, [:deterministic])
end

defimpl Comn.Merkel, for: Any do
  def to_content(term), do: :erlang.term_to_binary(term, [:deterministic])
end
