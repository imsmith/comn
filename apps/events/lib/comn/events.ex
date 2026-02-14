defmodule Comn.Events do
  @moduledoc """
  Behaviour defining the interface for event systems.
  """

  alias Comn.Events.EventStruct

  @callback start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  @callback broadcast(EventStruct.t()) :: :ok | {:error, term()}
  @callback subscribe(topic :: String.t(), opts :: keyword()) :: :ok | {:error, term()}
  @callback unsubscribe(topic :: String.t(), opts :: keyword()) :: :ok | {:error, term()}
end
