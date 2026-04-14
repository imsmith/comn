defimpl Comn.Event, for: Tuple do
  def to_event({type, topic, data}) do
    {:ok, Comn.Events.EventStruct.new(type, topic, data)}
  end

  def to_event(_invalid) do
    {:error, :invalid_tuple}
  end
end
