defmodule Comn.Events do
  @moduledoc """
  Documentation for `Events`.
  """

  @doc """
  Behaviour defining the interface for event systems.

  ## Examples


  """
  alias Comn.Event.EventStruct, as: EventStruct

  @callback start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  @callback broadcast(EventStruct) :: :ok | {:error, term()}
  @callback subscribe(topic :: String.t(), opts :: keyword()) :: :ok | {:error, term()}
  @callback unsubscribe(topic :: String.t(), opts :: keyword()) :: :ok | {:error, term()}

end
