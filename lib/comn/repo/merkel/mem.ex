defmodule Comn.Repo.Merkel.Mem do
  @moduledoc false
  # ETS-backed merkel: a named table of {address, %Node{}} plus the root under
  # the reserved key :_head. Addresses are sha256 hex. The table dies with the
  # process that opened it; nothing is durable, so close is drop.

  @behaviour Comn.Repo.Merkel.Backend

  alias Comn.Errors.Registry, as: ErrReg
  alias Comn.Repo.Merkel.Node

  @head_key :_head
  @algo :sha256

  @impl true
  def open(name, _opts) when is_atom(name) do
    case :ets.whereis(name) do
      :undefined ->
        :ets.new(name, [:set, :public, :named_table])
        :ets.insert(name, {@head_key, nil})
        {:ok, name}

      _ ->
        {:error, ErrReg.error!("repo.merkel/already_exists", field: name)}
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
  def put(name, content) when is_binary(content) do
    with :ok <- ensure_exists(name) do
      [{@head_key, parent}] = :ets.lookup(name, @head_key)
      content_address = hash(content)
      address = hash(link_bytes(parent, content_address))

      node = %Node{
        address: address,
        parent: parent,
        content_address: content_address,
        content: content,
        algo: @algo
      }

      :ets.insert(name, {address, node})
      :ets.insert(name, {@head_key, address})
      {:ok, address}
    end
  end

  @impl true
  def node(name, address) do
    with :ok <- ensure_exists(name) do
      case :ets.lookup(name, address) do
        [{^address, %Node{} = node}] -> {:ok, node}
        _ -> {:error, ErrReg.error!("repo.merkel/unknown_address", field: address)}
      end
    end
  end

  @impl true
  def head(name) do
    with :ok <- ensure_exists(name) do
      [{@head_key, root}] = :ets.lookup(name, @head_key)
      {:ok, root}
    end
  end

  @impl true
  def length(name) do
    with :ok <- ensure_exists(name), do: {:ok, :ets.info(name, :size) - 1}
  end

  @impl true
  def check(_name, %Node{address: a, parent: p, content_address: ca, content: c}) do
    if hash(c) == ca and hash(link_bytes(p, ca)) == a, do: :ok, else: :tampered
  end

  defp hash(bytes), do: Base.encode16(:crypto.hash(@algo, bytes), case: :lower)
  defp link_bytes(parent, content_address), do: "#{@algo}\n#{parent}\n#{content_address}"

  defp ensure_exists(name) do
    case :ets.whereis(name) do
      :undefined -> {:error, ErrReg.error!("repo.merkel/not_found", field: name)}
      _ -> :ok
    end
  end
end
