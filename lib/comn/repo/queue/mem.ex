defmodule Comn.Repo.Queue.Mem do
  @moduledoc false
  @behaviour Comn.Repo.Queue.Backend

  @impl true
  def open(_name, _opts), do: {:ok, :stub_state}
  @impl true
  def close(_state), do: :ok
  @impl true
  def push(_state, _item), do: {:error, :not_implemented}
  @impl true
  def reserve(_state), do: :empty
  @impl true
  def ack(_state, _token), do: :ok
  @impl true
  def release(_state, _token), do: :ok
  @impl true
  def peek(_state, _n), do: []
  @impl true
  def size(_state), do: 0
  @impl true
  def find(_state, _fun), do: :not_found
  @impl true
  def remove(_state, _fun), do: :not_found
end
