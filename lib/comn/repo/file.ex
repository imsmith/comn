defmodule Comn.Repo.File do
  @moduledoc """
  Files, through a lifecycle state machine.

  Public, backend-agnostic facade. Callers go through this module; the
  backend is a word in one option to `open/2`. Backends: `:local`
  (filesystem), `:nfs` (a mount point with stale-handle detection), and
  `:ipfs` (content-addressed, via the daemon's HTTP API).

  A file is a value with a state, so the verbs that advance it (`load/2`,
  `write/3`, and the `Comn.Repo` `set/2`) return a new handle:

           ┌→ stream → cast
  open → load ┤
           ├→ read → close
           └→ write → close

  Every path is confined: `:local` requires `root:` and `:nfs` requires
  `mount:`, and a path that resolves outside it is `repo.file/outside_root`
  (see `Comn.Repo.File.Root`). Using a handle in the wrong state is
  `repo.file/invalid_state`. A file of
  events is a log: `set(f, event: e)` appends one encoded line and
  `observe(f, as: :events)` streams them back.

  This module also remains the behaviour older backends implement directly;
  `Comn.Repo.File.Local`, `NFS`, and `IPFS` keep their public surface.

  ## Examples

      iex> path = Path.join(System.tmp_dir!(), "file_doc_#{:erlang.unique_integer([:positive])}.txt")
      iex> File.write!(path, "hello")
      iex> {:ok, f} = Comn.Repo.File.open(path, root: System.tmp_dir!())
      iex> {:ok, f} = Comn.Repo.File.load(f)
      iex> {:ok, "hello"} = Comn.Repo.File.read(f)
      iex> Comn.Repo.File.drop(f)
      :ok
  """

  @behaviour Comn
  @behaviour Comn.Repo

  alias Comn.Repo.{Handle, Lifecycle}

  @typedoc "Opaque file handle. Treat as a black box."
  @type t :: Handle.t()

  @backends %{
    local: Comn.Repo.File.Adapter,
    nfs: Comn.Repo.File.Adapter,
    ipfs: Comn.Repo.File.Adapter
  }

  @impl Comn.Repo
  def backends, do: @backends

  # ---- behaviour for direct backends (kept for Local, NFS, IPFS) ----

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

  # ---- lifecycle ----

  @doc """
  Opens a file by path (`:local`, `:nfs`) or content id (`:ipfs`); the
  handle starts in the `:open` state.

  Options: `:backend` — `:local` (default), `:nfs`, `:ipfs`, or a module
  implementing the private backend contract; `:root` (required) and
  `:mode` for local files, `:mount` (required) for NFS, `:api` for IPFS.
  A relative path is joined to the root; an absolute one must be under it.

  Errors: `repo.file/invalid_opts`, `repo.file/outside_root`,
  `repo.file/stale_handle`, `repo.file/ipfs_error`, or an OS reason such
  as `:enoent`.
  """
  @spec open(term(), keyword()) :: {:ok, t()} | {:error, term()}
  def open(path_or_ref, opts \\ []) when is_list(opts),
    do: Lifecycle.open(__MODULE__, path_or_ref, Keyword.put_new(opts, :backend, :local))

  @doc "Closes the underlying file. Idempotent."
  @spec close(t()) :: :ok
  def close(%Handle{} = h), do: Lifecycle.close(h)

  @doc "Closes and deletes (or unpins) the file. Idempotent."
  @spec drop(t()) :: :ok
  def drop(%Handle{} = h), do: Lifecycle.drop(h)

  # ---- file verbs ----

  @doc "Loads the content into the handle's buffer (`:open` to `:loaded`). Returns the new handle."
  @spec load(t(), keyword()) :: {:ok, t()} | {:error, term()}
  def load(%Handle{backend: b, state: s} = h, opts \\ []),
    do: Lifecycle.rebind(h, b.load(s, opts))

  @doc "A lazy stream over the loaded content."
  @spec stream(t(), keyword()) :: {:ok, Enumerable.t()} | {:error, term()}
  def stream(%Handle{backend: b, state: s}, opts \\ []), do: b.stream(s, opts)

  @doc "Broadcasts the loaded content to the EventBus."
  @spec cast(t(), keyword()) :: :ok | {:error, term()}
  def cast(%Handle{backend: b, state: s}, opts \\ []), do: b.cast(s, opts)

  @doc "The loaded content as a binary."
  @spec read(t(), keyword()) :: {:ok, binary()} | {:error, term()}
  def read(%Handle{backend: b, state: s}, opts \\ []), do: b.read(s, opts)

  @doc "Writes `data` through the handle. Returns the new handle (IPFS gets a new content id)."
  @spec write(t(), iodata(), keyword()) :: {:ok, t()} | {:error, term()}
  def write(%Handle{backend: b, state: s} = h, data, opts \\ []),
    do: Lifecycle.rebind(h, b.write(s, data, opts))

  # ---- @behaviour Comn.Repo ----

  @impl Comn.Repo
  def describe(%Handle{backend: b, state: s}), do: b.describe(s)

  @doc "`get(f, [])` is the loaded buffer; `get(f, id: event_id)` finds one event line."
  @impl Comn.Repo
  def get(%Handle{backend: b, state: s}, opts), do: b.get(s, opts)

  @doc "`set(f, event: e)` appends one encoded event line; `set(f, value: data)` writes data. Returns the new handle."
  @impl Comn.Repo
  def set(%Handle{backend: b, state: s} = h, opts), do: Lifecycle.rebind(h, b.set(s, opts))

  @impl Comn.Repo
  def delete(%Handle{backend: b, state: s}, opts), do: b.delete(s, opts)

  @impl Comn.Repo
  def observe(%Handle{backend: b, state: s}, opts \\ []), do: b.observe(s, opts)

  # ---- @behaviour Comn ----

  @impl Comn
  def look,
    do:
      "File — lifecycle state machine for file I/O (open, load, stream, cast, read, write, close)"

  @impl Comn
  def recon do
    %{
      callbacks: [:open, :close, :drop, :load, :stream, :cast, :read, :write],
      backends: Map.keys(@backends),
      extends: Comn.Repo,
      states: [:open, :loaded, :closed],
      type: :facade
    }
  end

  @impl Comn
  def choices, do: %{backends: ["local", "nfs", "ipfs"]}

  @impl Comn
  def act(%{action: :open, path: p, opts: o}), do: open(p, o)
  def act(%{action: :open, path: p}), do: open(p, [])
  def act(input), do: Comn.unknown_action(input)
end
