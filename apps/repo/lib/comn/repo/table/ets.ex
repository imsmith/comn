defmodule Comn.Repo.Table.ETS do
  @moduledoc """
  ETS-backed implementation of Comn.Repo and Comn.Repo.Table.

  Provides a simple key-value store using Erlang Term Storage.
  Tables are created as named_table, public, set by default.
  """

  @behaviour Comn.Repo
  @behaviour Comn.Repo.Table

  # Comn.Repo.Table callbacks

  @impl Comn.Repo.Table
  def create(name, opts \\ []) when is_atom(name) do
    ets_opts = Keyword.get(opts, :ets_opts, [:named_table, :public, :set])

    try do
      tid = :ets.new(name, ets_opts)
      {:ok, tid}
    rescue
      ArgumentError -> {:error, {:already_exists, name}}
    end
  end

  @impl Comn.Repo.Table
  def drop(name) when is_atom(name) do
    case table_exists?(name) do
      true ->
        :ets.delete(name)
        :ok

      false ->
        {:error, {:not_found, name}}
    end
  end

  @impl Comn.Repo.Table
  def keys(name) when is_atom(name) do
    case table_exists?(name) do
      true ->
        keys = :ets.foldl(fn {k, _v}, acc -> [k | acc] end, [], name)
        {:ok, Enum.reverse(keys)}

      false ->
        {:error, {:not_found, name}}
    end
  end

  @impl Comn.Repo.Table
  def count(name) when is_atom(name) do
    case table_exists?(name) do
      true -> {:ok, :ets.info(name, :size)}
      false -> {:error, {:not_found, name}}
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
        {:error, {:not_found, name}}
    end
  end

  @impl Comn.Repo
  def get(name, opts) when is_atom(name) do
    key = Keyword.fetch!(opts, :key)

    case table_exists?(name) do
      true ->
        case :ets.lookup(name, key) do
          [{^key, value}] -> {:ok, value}
          [] -> {:error, {:not_found, key}}
        end

      false ->
        {:error, {:not_found, name}}
    end
  end

  @impl Comn.Repo
  def set(name, opts) when is_atom(name) do
    key = Keyword.fetch!(opts, :key)
    value = Keyword.fetch!(opts, :value)

    case table_exists?(name) do
      true ->
        :ets.insert(name, {key, value})
        :ok

      false ->
        {:error, {:not_found, name}}
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
        {:error, {:not_found, name}}
    end
  end

  @impl Comn.Repo
  def observe(name, _opts) when is_atom(name) do
    case table_exists?(name) do
      true ->
        :ets.foldl(fn {k, v}, acc -> [{k, v} | acc] end, [], name)
        |> Enum.reverse()

      false ->
        {:error, {:not_found, name}}
    end
  end

  # Helpers

  defp table_exists?(name) do
    case :ets.info(name) do
      :undefined -> false
      _ -> true
    end
  end
end
