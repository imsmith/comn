defimpl Comn.Event, for: Map do
  def to_event(%{"type" => type, "topic" => topic, "data" => data}) do
    {:ok, Comn.Events.EventStruct.new(String.to_existing_atom(type), topic, data)}
  rescue
    ArgumentError ->
      {:error, Comn.Errors.Registry.error!("events/invalid_type", message: "unknown event type: #{type}")}
  end

  def to_event(%{type: type, topic: topic, data: data}) do
    {:ok, Comn.Events.EventStruct.new(type, topic, data)}
  end

  def to_event(_invalid) do
    {:error, :missing_keys}
  end
end
