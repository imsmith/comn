defmodule Comn.Repo.Table.ETS do
  @moduledoc """
  ETS-backed implementation of `Comn.Repo` and `Comn.Repo.Table`.

  In-memory key-value store using Erlang Term Storage. Tables default to
  `[:named_table, :public, :set]`.

  Implements `@behaviour Comn` for uniform introspection.

  ## Examples

      iex> {:ok, _} = Comn.Repo.Table.ETS.create(:doctest_table)
      iex> :ok = Comn.Repo.Table.ETS.set(:doctest_table, key: "k", value: "v")
      iex> {:ok, "v"} = Comn.Repo.Table.ETS.get(:doctest_table, key: "k")
      iex> {:ok, 1} = Comn.Repo.Table.ETS.count(:doctest_table)
      iex> :ok = Comn.Repo.Table.ETS.drop(:doctest_table)

      iex> Comn.Repo.Table.ETS.look()
      "ETS — in-memory key-value store backed by Erlang Term Storage"
  """

  alias Comn.Errors.Registry, as: ErrReg

  @behaviour Comn
  @behaviour Comn.Repo
  @behaviour Comn.Repo.Table

  # Comn.Repo.Table callbacks

  @impl Comn.Repo.Table
  def create(name, opts \\ []) when is_atom(name) do
    if table_exists?(name) do
      {:error, ErrReg.error!("repo.table/already_exists", field: name)}
    else
      ets_opts = Keyword.get(opts, :ets_opts, [:named_table, :public, :set])
      {:ok, :ets.new(name, ets_opts)}
    end
  end

  @impl Comn.Repo.Table
  def drop(name) when is_atom(name) do
    case table_exists?(name) do
      true ->
        :ets.delete(name)
        :ok

      false ->
        {:error, ErrReg.error!("repo.table/not_found", field: name)}
    end
  end

  @impl Comn.Repo.Table
  def keys(name) when is_atom(name) do
    case table_exists?(name) do
      true ->
        keys = :ets.foldl(fn {k, _v}, acc -> [k | acc] end, [], name)
        {:ok, Enum.reverse(keys)}

      false ->
        {:error, ErrReg.error!("repo.table/not_found", field: name)}
    end
  end

  @impl Comn.Repo.Table
  def count(name) when is_atom(name) do
    case table_exists?(name) do
      true -> {:ok, :ets.info(name, :size)}
      false -> {:error, ErrReg.error!("repo.table/not_found", field: name)}
    end
  end

  # Comn.Repo callbacks

  @impl Comn.Repo
  def describe(name) when is_atom(name) do
    case table_exists?(name) do
      true ->
        info = :ets.info(name)
        {:ok, Map.new(info)}

      false ->
        {:error, ErrReg.error!("repo.table/not_found", field: name)}
    end
  end

  @impl Comn.Repo
  def get(name, [id: id]) when is_atom(name) do
    case get(name, key: id) do
      {:ok, %Comn.Events.EventStruct{} = e} -> {:ok, e}
      _ -> Comn.Repo.not_found(id)
    end
  end

  def get(name, opts) when is_atom(name) do
    key = Keyword.fetch!(opts, :key)

    case table_exists?(name) do
      true ->
        case :ets.lookup(name, key) do
          [{^key, value}] -> {:ok, value}
          [] -> {:error, ErrReg.error!("repo.table/not_found", field: key)}
        end

      false ->
        {:error, ErrReg.error!("repo.table/not_found", field: name)}
    end
  end

  @impl Comn.Repo
  def set(name, [event: _] = opts) when is_atom(name) do
    with {:ok, e} <- Comn.Repo.fetch_event(opts), do: set(name, key: e.id, value: e)
  end

  def set(name, opts) when is_atom(name) do
    key = Keyword.fetch!(opts, :key)
    value = Keyword.fetch!(opts, :value)

    case table_exists?(name) do
      true ->
        :ets.insert(name, {key, value})
        :ok

      false ->
        {:error, ErrReg.error!("repo.table/not_found", field: name)}
    end
  end

  @impl Comn.Repo
  def delete(name, opts) when is_atom(name) do
    key = Keyword.fetch!(opts, :key)

    case table_exists?(name) do
      true ->
        :ets.delete(name, key)
        :ok

      false ->
        {:error, ErrReg.error!("repo.table/not_found", field: name)}
    end
  end

  @impl Comn.Repo
  def observe(name, opts) when is_atom(name) do
    case table_exists?(name) do
      true ->
        if Comn.Repo.events_view?(opts),
          do: for({_k, %Comn.Events.EventStruct{} = e} <- :ets.tab2list(name), do: e),
          else: :ets.foldl(fn {k, v}, acc -> [{k, v} | acc] end, [], name) |> Enum.reverse()

      false ->
        {:error, ErrReg.error!("repo.table/not_found", field: name)}
    end
  end

  # Comn callbacks

  @impl Comn
  def look, do: "ETS — in-memory key-value store backed by Erlang Term Storage"

  @impl Comn
  def recon do
    %{
      backend: :ets,
      default_opts: [:named_table, :public, :set],
      persistence: :memory,
      type: :implementation
    }
  end

  @impl Comn
  def choices do
    %{
      ets_opts: [":named_table", ":public", ":set", ":ordered_set", ":bag", ":duplicate_bag"]
    }
  end

  @impl Comn
  def act(%{action: :create, name: name} = input) do
    create(name, Map.get(input, :opts, []))
  end

  def act(%{action: :get, name: name, key: key}) do
    get(name, key: key)
  end

  def act(%{action: :set, name: name, key: key, value: value}) do
    set(name, key: key, value: value)
  end

  def act(%{action: :delete, name: name, key: key}) do
    delete(name, key: key)
  end

  def act(input), do: Comn.unknown_action(input)

  # Helpers

  defp table_exists?(name) do
    case :ets.info(name) do
      :undefined -> false
      _ -> true
    end
  end
end
