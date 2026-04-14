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

  @doc """
  Opens a file by path or reference, returning a handle in the `:open` state.

  Errors: OS-level errors (`:enoent`, `:eacces`), `{:stale_handle, path}` (NFS),
  `{:ipfs_error, status, body}` (IPFS).
  """
  @callback open(path_or_ref :: term(), opts :: keyword()) ::
              {:ok, handle()} | {:error, term()}

  @doc """
  Loads file content into the handle's buffer, transitioning to `:loaded`.

  Errors: `{:invalid_state, state, :expected_open}` (`repo.file/invalid_state`),
  `{:stale_handle, path}` (`repo.file/stale_handle`).
  """
  @callback load(handle(), opts :: keyword()) ::
              {:ok, handle()} | {:error, term()}

  @doc """
  Returns a lazy stream over the loaded file's content.

  Errors: `{:invalid_state, state, :expected_loaded}` (`repo.file/invalid_state`).
  """
  @callback stream(handle(), opts :: keyword()) ::
              {:ok, Enumerable.t()} | {:error, term()}

  @doc """
  Broadcasts the loaded file's content to the EventBus (fire-and-forget).

  Errors: `{:invalid_state, state, :expected_loaded}` (`repo.file/invalid_state`).
  """
  @callback cast(handle(), opts :: keyword()) ::
              :ok | {:error, term()}

  @doc """
  Reads the loaded file's buffered content as a binary.

  Errors: `{:invalid_state, state, :expected_loaded}` (`repo.file/invalid_state`).
  """
  @callback read(handle(), opts :: keyword()) ::
              {:ok, binary()} | {:error, term()}

  @doc """
  Writes data through the handle. Returns an updated handle (may change path
  for content-addressed backends like IPFS).

  Errors: `{:invalid_state, state, :expected_loaded}` (`repo.file/invalid_state`),
  `{:ipfs_error, status, body}` (`repo.file/ipfs_error`).
  """
  @callback write(handle(), data :: iodata(), opts :: keyword()) ::
              {:ok, handle()} | {:error, term()}

  @doc """
  Closes the file handle and releases resources.

  Errors: `{:invalid_state, state, :expected_open_or_loaded}` (`repo.file/invalid_state`).
  """
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
