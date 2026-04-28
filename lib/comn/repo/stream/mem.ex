defmodule Comn.Repo.Stream.Mem do
  @moduledoc """
  ETS-backed in-memory implementation of `Comn.Repo.Stream`.

  Each stream is a named ETS `:ordered_set` with integer offsets as keys
  and `Comn.Events.EventStruct` as values. Offsets are monotonic and
  start at 1, allocated via `:ets.update_counter/3` against a counter
  row stored at the reserved key `:_next_offset`.

  No supervised process is needed — the ETS table itself is the stream.
  Drop the table to delete the stream.

  ## Caveats

  - Tables are owned by the calling process. If that process exits, the
    table dies with it. For long-lived streams, call `create/1` from a
    long-lived process (e.g. an application supervisor child).
  - Counter row uses key `:_next_offset` (an atom) which never collides
    with valid integer offsets.

  Implements `@behaviour Comn.Repo.Stream` and `@behaviour Comn`.

  ## Examples

      iex> name = String.to_atom("mem_doc_#{:erlang.unique_integer([:positive])}")
      iex> :ok = Comn.Repo.Stream.Mem.create(name)
      iex> event = Comn.Events.EventStruct.new(:test, "doc.example", %{})
      iex> {:ok, offset} = Comn.Repo.Stream.Mem.append(name, event)
      iex> {:ok, ^offset} = Comn.Repo.Stream.Mem.head(name)
      iex> Comn.Repo.Stream.Mem.drop(name)
      :ok
  """

  @behaviour Comn
  @behaviour Comn.Repo
  @behaviour Comn.Repo.Stream

  alias Comn.Errors.Registry, as: ErrReg
  alias Comn.Events.EventStruct

  @counter_key :_next_offset

  # Lifecycle

  @doc """
  Creates a new stream as a named ETS table.

  Returns `{:error, ErrorStruct}` with code `repo.stream/already_exists`
  if a stream of this name already exists.
  """
  @spec create(atom()) :: :ok | {:error, term()}
  def create(name) when is_atom(name) do
    case :ets.whereis(name) do
      :undefined ->
        :ets.new(name, [:ordered_set, :public, :named_table])
        :ets.insert(name, {@counter_key, 0})
        :ok

      _ref ->
        {:error, ErrReg.error!("repo.stream/already_exists", field: name)}
    end
  end

  @doc "Drops the stream's ETS table. Idempotent."
  @spec drop(atom()) :: :ok
  def drop(name) when is_atom(name) do
    case :ets.whereis(name) do
      :undefined -> :ok
      _ -> :ets.delete(name) && :ok
    end
  end

  # Comn.Repo.Stream

  @impl Comn.Repo.Stream
  def append(name, %EventStruct{} = event) when is_atom(name) do
    with :ok <- ensure_exists(name) do
      offset = :ets.update_counter(name, @counter_key, 1)
      :ets.insert(name, {offset, event})
      {:ok, offset}
    end
  end

  def append(name, _not_event) when is_atom(name) do
    case ensure_exists(name) do
      :ok -> {:error, ErrReg.error!("repo.stream/invalid_event")}
      err -> err
    end
  end

  @impl Comn.Repo.Stream
  def append_many(name, events) when is_atom(name) and is_list(events) do
    with :ok <- ensure_exists(name),
         :ok <- validate_events(events) do
      offsets =
        Enum.map(events, fn event ->
          offset = :ets.update_counter(name, @counter_key, 1)
          :ets.insert(name, {offset, event})
          offset
        end)

      {:ok, offsets}
    end
  end

  @impl Comn.Repo.Stream
  def read(name, cursor, count) when is_atom(name) and is_integer(count) and count > 0 do
    with :ok <- ensure_exists(name) do
      do_read(name, cursor, count)
    end
  end

  @impl Comn.Repo.Stream
  def head(name) when is_atom(name) do
    # Erlang term order: numbers < atoms. So in an ordered_set the
    # counter atom sorts after all integer offsets — the last integer
    # offset is the one immediately before the counter row.
    with :ok <- ensure_exists(name) do
      case :ets.prev(name, @counter_key) do
        :"$end_of_table" -> {:ok, nil}
        offset -> {:ok, offset}
      end
    end
  end

  @impl Comn.Repo.Stream
  def tail(name) when is_atom(name) do
    with :ok <- ensure_exists(name) do
      case :ets.first(name) do
        :"$end_of_table" -> {:ok, nil}
        @counter_key -> {:ok, nil}
        offset -> {:ok, offset}
      end
    end
  end

  # Comn.Repo

  @impl Comn.Repo
  def describe(name) when is_atom(name) do
    with :ok <- ensure_exists(name),
         {:ok, head} <- head(name),
         {:ok, tail} <- tail(name) do
      count = :ets.info(name, :size) - 1
      {:ok, %{name: name, head: head, tail: tail, count: count}}
    end
  end

  @impl Comn.Repo
  def get(name, opts) when is_atom(name) and is_list(opts) do
    with :ok <- ensure_exists(name) do
      offset = Keyword.get(opts, :offset)

      case :ets.lookup(name, offset) do
        [{^offset, %EventStruct{} = event}] -> {:ok, event}
        _ -> {:error, ErrReg.error!("repo.stream/invalid_offset", field: offset)}
      end
    end
  end

  @impl Comn.Repo
  def set(name, opts) when is_atom(name) and is_list(opts) do
    case Keyword.fetch(opts, :event) do
      {:ok, event} -> append(name, event)
      :error -> {:error, ErrReg.error!("repo.stream/invalid_event")}
    end
  end

  @impl Comn.Repo
  def delete(_name, _opts) do
    {:error, ErrReg.error!("repo.stream/append_only")}
  end

  @impl Comn.Repo
  def observe(name, _opts) when is_atom(name) do
    Stream.resource(
      fn -> {name, :head} end,
      fn
        :done ->
          {:halt, nil}

        {n, cursor} ->
          case do_read(n, cursor, 100) do
            {:ok, []} ->
              {:halt, nil}

            {:ok, batch} ->
              {last_offset, _} = List.last(batch)
              {batch, {n, last_offset + 1}}
          end
      end,
      fn _ -> :ok end
    )
  end

  # Comn

  @impl Comn
  def look, do: "Stream.Mem — ETS-backed in-memory append-only stream"

  @impl Comn
  def recon do
    %{
      type: :implementation,
      implements: Comn.Repo.Stream,
      backend: :ets,
      durable?: false
    }
  end

  @impl Comn
  def choices do
    %{actions: [:create, :drop, :append, :read, :head, :tail]}
  end

  @impl Comn
  def act(%{action: :create, name: n}), do: {:ok, create(n)}
  def act(%{action: :drop, name: n}), do: {:ok, drop(n)}
  def act(%{action: :append, name: n, event: e}), do: append(n, e)
  def act(%{action: :read, name: n, from: f, count: c}), do: read(n, f, c)
  def act(%{action: :head, name: n}), do: head(n)
  def act(%{action: :tail, name: n}), do: tail(n)
  def act(_), do: {:error, :unknown_action}

  # Internals

  defp ensure_exists(name) do
    case :ets.whereis(name) do
      :undefined -> {:error, ErrReg.error!("repo.stream/not_found", field: name)}
      _ -> :ok
    end
  end

  defp validate_events(events) do
    if Enum.all?(events, &match?(%EventStruct{}, &1)) do
      :ok
    else
      {:error, ErrReg.error!("repo.stream/invalid_event")}
    end
  end

  defp do_read(name, :head, count) do
    rows = take_forward(name, :ets.first(name), count, [])
    {:ok, rows}
  end

  defp do_read(name, :tail, count) do
    rows = take_backward(name, :ets.last(name), count, [])
    {:ok, rows}
  end

  defp do_read(name, offset, count) when is_integer(offset) do
    rows = take_forward(name, offset, count, [])
    {:ok, rows}
  end

  defp take_forward(_name, :"$end_of_table", _n, acc), do: Enum.reverse(acc)
  defp take_forward(_name, _key, 0, acc), do: Enum.reverse(acc)

  defp take_forward(name, @counter_key, n, acc) do
    take_forward(name, :ets.next(name, @counter_key), n, acc)
  end

  defp take_forward(name, key, n, acc) when is_integer(key) do
    case :ets.lookup(name, key) do
      [{^key, %EventStruct{} = event}] ->
        take_forward(name, :ets.next(name, key), n - 1, [{key, event} | acc])

      _ ->
        Enum.reverse(acc)
    end
  end

  defp take_backward(_name, :"$end_of_table", _n, acc), do: acc
  defp take_backward(_name, _key, 0, acc), do: acc

  defp take_backward(name, @counter_key, n, acc) do
    take_backward(name, :ets.prev(name, @counter_key), n, acc)
  end

  defp take_backward(name, key, n, acc) when is_integer(key) do
    case :ets.lookup(name, key) do
      [{^key, %EventStruct{} = event}] ->
        take_backward(name, :ets.prev(name, key), n - 1, [{key, event} | acc])

      _ ->
        acc
    end
  end
end
