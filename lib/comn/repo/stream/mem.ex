defmodule Comn.Repo.Stream.Mem do
  @moduledoc false
  # ETS-backed in-memory stream backend. The named :ordered_set table is the
  # stream: integer offsets as keys (monotonic from 1 via a counter row at
  # the reserved key :_next_offset), EventStructs as values. No process; the
  # table dies with the process that opened it. Nothing is durable, so close
  # and drop are the same.
  #
  # ponytail: dispatch runs in the appender, so concurrent appenders can
  # deliver out of order. Offsets make gaps detectable; read/3 fills them.

  @behaviour Comn.Repo.Stream.Backend

  alias Comn.Errors.Registry, as: ErrReg

  @counter_key :_next_offset

  @impl true
  def open(name, _opts) when is_atom(name) do
    case :ets.whereis(name) do
      :undefined ->
        :ets.new(name, [:ordered_set, :public, :named_table])
        :ets.insert(name, {@counter_key, 0})
        {:ok, name}

      _ref ->
        {:error, ErrReg.error!("repo.stream/already_exists", field: name)}
    end
  end

  @impl true
  def close(name), do: drop(name)

  @impl true
  def drop(name) do
    if :ets.whereis(name) != :undefined, do: :ets.delete(name)
    :ok
  end

  @impl true
  def append(name, events) do
    with :ok <- ensure_exists(name) do
      offsets =
        for event <- events do
          offset = :ets.update_counter(name, @counter_key, 1)
          :ets.insert(name, {offset, event})
          Comn.Repo.Stream.notify(name, offset, event)
          offset
        end

      {:ok, offsets}
    end
  end

  @impl true
  def read(name, cursor, count) do
    with :ok <- ensure_exists(name) do
      case cursor do
        :head -> {:ok, forward(name, first_offset(name), count)}
        :tail -> {:ok, backward(name, :ets.last(name), count, [])}
        o when is_integer(o) -> {:ok, forward(name, o, count)}
        bad -> {:error, ErrReg.error!("repo.stream/invalid_offset", field: inspect(bad))}
      end
    end
  end

  @impl true
  def head(name) do
    with :ok <- ensure_exists(name) do
      # the atom counter key sorts last; the newest offset is just before it
      case :ets.prev(name, @counter_key) do
        o when is_integer(o) -> {:ok, o}
        _ -> {:ok, nil}
      end
    end
  end

  @impl true
  def tail(name) do
    with :ok <- ensure_exists(name), do: {:ok, first_offset(name)}
  end

  @impl true
  def count(name) do
    with :ok <- ensure_exists(name), do: {:ok, :ets.info(name, :size) - 1}
  end

  @impl true
  def subscribe(_name), do: :ok

  # Internals

  defp ensure_exists(name) do
    case :ets.whereis(name) do
      :undefined -> {:error, ErrReg.error!("repo.stream/not_found", field: name)}
      _ -> :ok
    end
  end

  # integer keys sort before the atom counter key, so the first integer is :ets.first
  defp first_offset(name) do
    case :ets.first(name) do
      o when is_integer(o) -> o
      _ -> nil
    end
  end

  defp forward(_name, nil, _n), do: []

  defp forward(name, from, n) do
    :ets.select(
      name,
      [{{:"$1", :"$2"}, [{:is_integer, :"$1"}, {:>=, :"$1", from}], [{{:"$1", :"$2"}}]}],
      n
    )
    |> case do
      {rows, _cont} -> rows
      :"$end_of_table" -> []
    end
  end

  defp backward(_name, _key, 0, acc), do: acc
  defp backward(_name, :"$end_of_table", _n, acc), do: acc

  defp backward(name, @counter_key, n, acc),
    do: backward(name, :ets.prev(name, @counter_key), n, acc)

  defp backward(name, key, n, acc) when is_integer(key) do
    [{^key, event}] = :ets.lookup(name, key)
    backward(name, :ets.prev(name, key), n - 1, [{key, event} | acc])
  end
end
