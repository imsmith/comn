defprotocol Comn.Event do
  @moduledoc """
  Protocol for converting arbitrary terms into `Comn.Events.EventStruct`.

  Implement this protocol for any type that should be convertible to a
  structured event. Built-in implementations handle maps, tuples, and
  `EventStruct` passthrough.

  ## Examples

      iex> {:ok, event} = Comn.Event.to_event(%{type: :info, topic: "test", data: %{}})
      iex> event.type
      :info

      iex> {:ok, event} = Comn.Event.to_event({:warn, "test.topic", %{msg: "hi"}})
      iex> event.topic
      "test.topic"
  """

  @doc """
  Converts a term into a `Comn.Events.EventStruct`.

  Returns `{:ok, event_struct}` or `{:error, reason}`.
  """
  @spec to_event(t) :: {:ok, Comn.Events.EventStruct.t()} | {:error, term()}
  def to_event(term)
end
