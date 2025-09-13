defimpl Comn.Event, for: Tuple do
  def to_event({type, topic, data}) do
    Comn.Events.EventStruct.new(type, topic, data)
  end
end
