defmodule Comn.Repo.Column.ETSAdapter do
  @moduledoc false
  # Backend contract over the public Comn.Repo.Column.ETS module. State is
  # the ETS store struct. Nothing is durable, so close is drop.

  @behaviour Comn.Repo.Column.Backend

  alias Comn.Repo.Column.ETS

  @impl true
  def open(name, opts) do
    with {:ok, store} <- ETS.create(name),
         :ok <- maybe_schema(store, Keyword.get(opts, :schema)) do
      {:ok, store}
    end
  end

  defp maybe_schema(_store, nil), do: :ok
  defp maybe_schema(store, schema), do: ETS.define_schema(store, schema)

  @impl true
  def close(store), do: drop(store)

  @impl true
  def drop(store), do: ETS.drop(store)

  @impl true
  defdelegate define_schema(store, schema), to: ETS
  @impl true
  defdelegate schema(store), to: ETS
  @impl true
  defdelegate append_row(store, row), to: ETS
  @impl true
  defdelegate append_rows(store, rows), to: ETS
  @impl true
  defdelegate flush(store), to: ETS
  @impl true
  defdelegate project(store, fields, filters), to: ETS
  @impl true
  defdelegate count(store, filters), to: ETS
  @impl true
  defdelegate describe(store), to: ETS
  @impl true
  defdelegate get(store, opts), to: ETS
  @impl true
  defdelegate set(store, opts), to: ETS
  @impl true
  defdelegate delete(store, opts), to: ETS
  @impl true
  defdelegate observe(store, opts), to: ETS
end
