defmodule Comn.Repo.Batch.MemAdapter do
  @moduledoc false
  # Backend contract over the public Comn.Repo.Batch.Mem GenServer. State is
  # the pid, linked to the opener like Queue.Mem. close flushes first so a
  # buffer is never silently lost; drop discards it.

  @behaviour Comn.Repo.Batch.Backend

  alias Comn.Repo.Batch.Mem

  @impl true
  def open(name, opts), do: Mem.start_link(Keyword.put(opts, :name, name))

  @impl true
  def close(pid) do
    if Process.alive?(pid) do
      _ = Mem.flush(pid)
      GenServer.stop(pid, :normal)
    end

    :ok
  end

  @impl true
  def drop(pid) do
    if Process.alive?(pid), do: GenServer.stop(pid, :normal)
    :ok
  end

  @impl true
  defdelegate add(pid, item), to: Mem
  @impl true
  defdelegate add_many(pid, items), to: Mem
  @impl true
  defdelegate flush(pid), to: Mem
  @impl true
  defdelegate pending(pid), to: Mem
  @impl true
  defdelegate config(pid), to: Mem
  @impl true
  defdelegate describe(pid), to: Mem
  @impl true
  defdelegate get(pid, opts), to: Mem
  @impl true
  defdelegate set(pid, opts), to: Mem
  @impl true
  defdelegate delete(pid, opts), to: Mem
  @impl true
  defdelegate observe(pid, opts), to: Mem
end
