defmodule Comn.Repo.Queue.Mem do
  @moduledoc false
  # ETS-backed in-memory queue. Backed by a GenServer that owns the
  # ETS table and serializes pushes, reserves, acks, and releases.
  # Tokens are monotonic positive integers.
  #
  # Items live in an ordered_set keyed by id (the token). A separate
  # ETS field tracks whether each item is reserved.

  @behaviour Comn.Repo.Queue.Backend

  use GenServer

  defmodule State do
    @moduledoc false
    @enforce_keys [:table, :discipline, :next_id]
    defstruct [:table, :discipline, :next_id]
  end

  # ---- Backend callbacks ----

  @impl true
  def open(name, opts) do
    discipline = Keyword.get(opts, :discipline, :fifo)
    GenServer.start_link(__MODULE__, {name, discipline})
  end

  @impl true
  def close(pid) do
    if Process.alive?(pid), do: GenServer.stop(pid, :normal), else: :ok
  end

  @impl true
  def push(pid, item),                do: GenServer.call(pid, {:push, item})
  @impl true
  def reserve(pid),                   do: GenServer.call(pid, :reserve)
  @impl true
  def ack(pid, token),                do: GenServer.call(pid, {:ack, token})
  @impl true
  def release(pid, token),            do: GenServer.call(pid, {:release, token})
  @impl true
  def peek(pid, n),                   do: GenServer.call(pid, {:peek, n})
  @impl true
  def size(pid),                      do: GenServer.call(pid, :size)
  @impl true
  def find(pid, fun),                 do: GenServer.call(pid, {:find, fun})
  @impl true
  def remove(pid, fun),               do: GenServer.call(pid, {:remove, fun})

  # ---- GenServer callbacks ----

  @impl true
  def init({_name, discipline}) do
    table = :ets.new(:comn_queue_mem, [:ordered_set, :private])
    {:ok, %State{table: table, discipline: discipline, next_id: 1}}
  end

  @impl true
  def handle_call({:push, item}, _from, %State{} = s) do
    :ets.insert(s.table, {s.next_id, false, item})
    {:reply, :ok, %{s | next_id: s.next_id + 1}}
  end

  def handle_call(:reserve, _from, %State{table: t, discipline: d} = s) do
    case head_available(t, d) do
      :none ->
        {:reply, :empty, s}

      {id, item} ->
        :ets.update_element(t, id, {2, true})
        {:reply, {:ok, {id, item}}, s}
    end
  end

  def handle_call({:ack, id}, _from, %State{table: t} = s) do
    :ets.delete(t, id)
    {:reply, :ok, s}
  end

  def handle_call({:release, id}, _from, %State{table: t} = s) do
    case :ets.lookup(t, id) do
      [{^id, _reserved, _item}] ->
        :ets.update_element(t, id, {2, false})
        {:reply, :ok, s}

      [] ->
        {:reply, :ok, s}
    end
  end

  def handle_call({:peek, n}, _from, %State{table: t, discipline: d} = s) do
    items = available_items(t, d) |> Enum.take(n) |> Enum.map(fn {_id, item} -> item end)
    {:reply, items, s}
  end

  def handle_call(:size, _from, %State{table: t} = s) do
    count = :ets.foldl(fn {_, _, _}, acc -> acc + 1 end, 0, t)
    {:reply, count, s}
  end

  def handle_call({:find, fun}, _from, %State{table: t, discipline: d} = s) do
    reply =
      available_items(t, d)
      |> Enum.find(fn {_id, item} -> fun.(item) end)
      |> case do
        nil         -> :not_found
        {_id, item} -> {:ok, item}
      end

    {:reply, reply, s}
  end

  def handle_call({:remove, fun}, _from, %State{table: t, discipline: d} = s) do
    reply =
      available_items(t, d)
      |> Enum.find(fn {_id, item} -> fun.(item) end)
      |> case do
        nil ->
          :not_found

        {id, item} ->
          :ets.delete(t, id)
          {:ok, item}
      end

    {:reply, reply, s}
  end

  # ---- helpers ----

  defp head_available(t, :fifo) do
    available_items(t, :fifo) |> Enum.take(1) |> List.first() |> head_or_none()
  end

  defp head_available(t, :lifo) do
    available_items(t, :lifo) |> Enum.take(1) |> List.first() |> head_or_none()
  end

  defp head_or_none(nil),              do: :none
  defp head_or_none({_id, _item} = h), do: h

  defp available_items(t, :fifo) do
    Stream.unfold(:ets.first(t), fn
      :"$end_of_table" -> nil
      key              -> {key, :ets.next(t, key)}
    end)
    |> Stream.map(fn k -> :ets.lookup(t, k) |> List.first() end)
    |> Stream.reject(fn {_id, reserved, _item} -> reserved end)
    |> Stream.map(fn {id, _r, item} -> {id, item} end)
  end

  defp available_items(t, :lifo) do
    Stream.unfold(:ets.last(t), fn
      :"$end_of_table" -> nil
      key              -> {key, :ets.prev(t, key)}
    end)
    |> Stream.map(fn k -> :ets.lookup(t, k) |> List.first() end)
    |> Stream.reject(fn {_id, reserved, _item} -> reserved end)
    |> Stream.map(fn {id, _r, item} -> {id, item} end)
  end
end
