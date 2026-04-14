defimpl Comn.Event, for: Map do
  def to_event(%{"type" => type, "topic" => topic, "data" => data}) do
    {:ok, Comn.Events.EventStruct.new(String.to_atom(type), topic, data)}
  end

  def to_event(%{type: type, topic: topic, data: data}) do
    {:ok, Comn.Events.EventStruct.new(type, topic, data)}
  end

  def to_event(_invalid) do
    {:error, :missing_keys}
  end
end
