defmodule Comn.Repo.Merkel.Backend do
  @moduledoc false
  # Private contract implemented by Comn.Repo.Merkel.{Mem, Git}. Callers go
  # through Comn.Repo.Merkel. Content arriving here is already canonical
  # bytes; the backend owns hashing, so addresses are opaque per backend.

  alias Comn.Repo.Merkel.Node

  @type state :: term()
  @type address :: String.t()

  @callback open(name :: atom(), opts :: keyword()) :: {:ok, state()} | {:error, term()}
  @callback close(state()) :: :ok
  @callback drop(state()) :: :ok
  @doc "Store `content` as a new node whose parent is the current head; return its address."
  @callback put(state(), content :: binary()) :: {:ok, address()} | {:error, term()}
  @callback node(state(), address()) :: {:ok, Node.t()} | {:error, term()}
  @callback head(state()) :: {:ok, address() | nil} | {:error, term()}
  @callback length(state()) :: {:ok, non_neg_integer()} | {:error, term()}
  @doc "Recheck one node's hashes against its stored content. The facade walks the chain."
  @callback check(state(), Node.t()) :: :ok | :tampered
end
