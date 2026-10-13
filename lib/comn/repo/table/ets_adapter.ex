defmodule Comn.Repo.Table.ETSAdapter do
  @moduledoc false
  # Backend contract over the public Comn.Repo.Table.ETS module. State is
  # the table name. Nothing is durable, so close is drop; drop is idempotent
  # where ETS.drop/1 is not.

  @behaviour Comn.Repo.Table.Backend

  alias Comn.Repo.Table.ETS

  @impl true
  def open(name, opts) do
    with {:ok, _} <- ETS.create(name, opts), do: {:ok, name}
  end

  @impl true
  def close(name), do: drop(name)

  @impl true
  def drop(name) do
    _ = ETS.drop(name)
    :ok
  end

  @impl true
  def get(name, key, _opts), do: ETS.get(name, key: key)

  @impl true
  def set(name, key, value, _opts), do: ETS.set(name, key: key, value: value)

  @impl true
  def delete(name, key, _opts), do: ETS.delete(name, key: key)

  @impl true
  def keys(name, _opts), do: ETS.keys(name)

  @impl true
  def count(name, _opts), do: ETS.count(name)

  @impl true
  def observe(name, _opts), do: ETS.observe(name, [])
end
