defmodule Comn.Repo.File do
  @moduledoc """
  Behaviour for file repository operations using a lifecycle state machine.

  State transitions:

           ┌→ stream → cast
  open → load ┤
           ├→ read → close
           └→ write → close
  """

  @type handle :: term()

  @callback open(path_or_ref :: term(), opts :: keyword()) ::
              {:ok, handle()} | {:error, term()}

  @callback load(handle(), opts :: keyword()) ::
              {:ok, handle()} | {:error, term()}

  @callback stream(handle(), opts :: keyword()) ::
              {:ok, Enumerable.t()} | {:error, term()}

  @callback cast(handle(), opts :: keyword()) ::
              :ok | {:error, term()}

  @callback read(handle(), opts :: keyword()) ::
              {:ok, binary()} | {:error, term()}

  @callback write(handle(), data :: iodata(), opts :: keyword()) ::
              {:ok, handle()} | {:error, term()}

  @callback close(handle(), opts :: keyword()) ::
              :ok | {:error, term()}
end
