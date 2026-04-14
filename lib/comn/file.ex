defmodule Comn.Repo.File do
  @moduledoc """
  Behaviour for file repository operations using a lifecycle state machine.

  Extends `Comn.Repo` with file-specific verbs: `open`, `load`, `stream`,
  `cast`, `read`, `write`, `close`. Implementations (`Local`, `NFS`, `IPFS`)
  follow the same state transitions.

  Also implements `@behaviour Comn` for uniform introspection.

  ## State transitions

           ┌→ stream → cast
  open → load ┤
           ├→ read → close
           └→ write → close

  ## Examples

      iex> Comn.Repo.File.look()
      "File — lifecycle state machine for file I/O (open, load, stream, cast, read, write, close)"

      iex> %{states: [:open, :loaded, :closed]} = Comn.Repo.File.recon()
  """

  @behaviour Comn

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

  @impl Comn
  def look, do: "File — lifecycle state machine for file I/O (open, load, stream, cast, read, write, close)"

  @impl Comn
  def recon do
    %{
      callbacks: [:open, :load, :stream, :cast, :read, :write, :close],
      extends: Comn.Repo,
      states: [:open, :loaded, :closed],
      type: :behaviour
    }
  end

  @impl Comn
  def choices do
    %{implementations: ["Local", "NFS", "IPFS"]}
  end

  @impl Comn
  def act(_input), do: {:error, :behaviour_only}
end
