defmodule Comn.Repo.Batch.Mem do
  @moduledoc """
  In-memory GenServer implementation of `Comn.Repo.Batch` and `Comn.Repo`.

  Buffers items in process state and flushes via a configurable callback.
  Supports both size-triggered and interval-triggered auto-flush.

  Implements `@behaviour Comn` for uniform introspection.

  ## Options

  - `:name` — process name (default: `Comn.Repo.Batch.Mem`)
  - `:max_size` — auto-flush at this buffer count (default: 1000)
  - `:interval_ms` — auto-flush on this interval (default: 5000, set to 0 to disable)
  - `:on_flush` — `(list() -> :ok | {:error, term()})` callback invoked with the batch

  ## Examples

      iex> Comn.Repo.Batch.Mem.look()
      "Batch.Mem — in-memory GenServer batch buffer with auto-flush"
  """

  use GenServer

  @behaviour Comn
  @behaviour Comn.Repo
  @behaviour Comn.Repo.Batch

  alias Comn.Errors.Registry, as: ErrReg

  @default_max_size 1000
  @default_interval_ms 5000

  # -- Client API --

  @doc """
  Starts a batch buffer process.

  Options: `:name`, `:max_size`, `:interval_ms`, `:on_flush`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  # -- Comn.Repo.Batch callbacks --

  @impl Comn.Repo.Batch
  def add(store \\ __MODULE__, item) do
    GenServer.call(store, {:add, [item]})
  end

  @impl Comn.Repo.Batch
  def add_many(store \\ __MODULE__, items) when is_list(items) do
    GenServer.call(store, {:add, items})
  end

  @impl Comn.Repo.Batch
  def flush(store \\ __MODULE__) do
    GenServer.call(store, :flush)
  end

  @impl Comn.Repo.Batch
  def pending(store \\ __MODULE__) do
    GenServer.call(store, :pending)
  end

  @impl Comn.Repo.Batch
  def config(store \\ __MODULE__) do
    GenServer.call(store, :config)
  end

  # -- Comn.Repo callbacks --

  @impl Comn.Repo
  def describe(store \\ __MODULE__) do
    GenServer.call(store, :describe)
  end

  @impl Comn.Repo
  def get(_store, _opts) do
    {:error, ErrReg.error!("repo.batch/flush_failed",
      message: "Batch stores are write-only; use the flush callback to consume data")}
  end

  @impl Comn.Repo
  def set(store \\ __MODULE__, opts) do
    item = Keyword.fetch!(opts, :value)
    add(store, item)
  end

  @impl Comn.Repo
  def delete(_store, _opts) do
    {:error, ErrReg.error!("repo.batch/flush_failed",
      message: "Batch stores are write-only; delete is not supported")}
  end

  @impl Comn.Repo
  def observe(store \\ __MODULE__, _opts) do
    GenServer.call(store, :observe)
  end

  # -- Comn callbacks --

  @impl Comn
  def look, do: "Batch.Mem — in-memory GenServer batch buffer with auto-flush"

  @impl Comn
  def recon do
    %{
      backend: :memory,
      process: :genserver,
      type: :implementation
    }
  end

  @impl Comn
  def choices do
    %{
      max_size: "auto-flush threshold (default: #{@default_max_size})",
      interval_ms: "auto-flush interval in ms (default: #{@default_interval_ms}, 0 to disable)"
    }
  end

  @impl Comn
  def act(%{action: :add, item: item} = input) do
    store = Map.get(input, :name, __MODULE__)
    add(store, item)
  end

  def act(%{action: :flush} = input) do
    store = Map.get(input, :name, __MODULE__)
    flush(store)
  end

  def act(_input), do: {:error, :unknown_action}

  # -- GenServer callbacks --

  @impl GenServer
  def init(opts) do
    max_size = Keyword.get(opts, :max_size, @default_max_size)
    interval_ms = Keyword.get(opts, :interval_ms, @default_interval_ms)
    on_flush = Keyword.get(opts, :on_flush, fn _items -> :ok end)

    state = %{
      buffer: [],
      count: 0,
      max_size: max_size,
      interval_ms: interval_ms,
      on_flush: on_flush,
      total_flushed: 0
    }

    if interval_ms > 0 do
      Process.send_after(self(), :tick, interval_ms)
    end

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:add, items}, _from, state) do
    new_buffer = state.buffer ++ items
    new_count = state.count + length(items)
    state = %{state | buffer: new_buffer, count: new_count}

    if new_count >= state.max_size do
      case do_flush(state) do
        {:ok, flushed, state} -> {:reply, :ok, state |> Map.update!(:total_flushed, &(&1 + flushed))}
        {:error, _} = err -> {:reply, err, state}
      end
    else
      {:reply, :ok, state}
    end
  end

  @impl GenServer
  def handle_call(:flush, _from, state) do
    case do_flush(state) do
      {:ok, flushed, state} ->
        {:reply, {:ok, flushed}, state |> Map.update!(:total_flushed, &(&1 + flushed))}

      {:error, _} = err ->
        {:reply, err, state}
    end
  end

  @impl GenServer
  def handle_call(:pending, _from, state) do
    {:reply, {:ok, state.count}, state}
  end

  @impl GenServer
  def handle_call(:config, _from, state) do
    {:reply, {:ok, %{
      max_size: state.max_size,
      interval_ms: state.interval_ms,
      total_flushed: state.total_flushed
    }}, state}
  end

  @impl GenServer
  def handle_call(:describe, _from, state) do
    {:reply, {:ok, %{
      pending: state.count,
      max_size: state.max_size,
      interval_ms: state.interval_ms,
      total_flushed: state.total_flushed,
      backend: __MODULE__
    }}, state}
  end

  @impl GenServer
  def handle_call(:observe, _from, state) do
    {:reply, state.buffer, state}
  end

  @impl GenServer
  def handle_info(:tick, state) do
    state =
      if state.count > 0 do
        case do_flush(state) do
          {:ok, flushed, state} -> Map.update!(state, :total_flushed, &(&1 + flushed))
          {:error, _} -> state
        end
      else
        state
      end

    if state.interval_ms > 0 do
      Process.send_after(self(), :tick, state.interval_ms)
    end

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # -- Private --

  defp do_flush(%{buffer: [], count: 0} = state), do: {:ok, 0, state}

  defp do_flush(%{buffer: buffer, count: count, on_flush: on_flush} = state) do
    case on_flush.(buffer) do
      :ok ->
        {:ok, count, %{state | buffer: [], count: 0}}

      {:error, _} = err ->
        err
    end
  end
end
