defmodule Comn.Repo.File.Local do
  @moduledoc """
  Local filesystem implementation of `Comn.Repo.File` and `Comn.Repo`.

  Follows the file lifecycle state machine (`open → load → read/write/stream → close`)
  against the local disk. Used directly or as the delegate for `Comn.Repo.File.NFS`.

  Implements `@behaviour Comn` for uniform introspection.

  ## Examples

      iex> Comn.Repo.File.Local.look()
      "File.Local — local filesystem file I/O with lifecycle state machine"

      iex> %{backend: :local_fs} = Comn.Repo.File.Local.recon()
  """

  alias Comn.Errors.Registry, as: ErrReg
  alias Comn.Repo.File.FileStruct

  @behaviour Comn
  @behaviour Comn.Repo
  @behaviour Comn.Repo.File

  # Comn.Repo.File callbacks

  @spec open(term(), keyword()) :: {:ok, Comn.Repo.File.handle()} | {:error, term()}
  @impl Comn.Repo.File
  def open(path, opts \\ []) do
    mode = Keyword.get(opts, :mode, [:read, :binary])

    case File.open(path, mode) do
      {:ok, io_device} ->
        {:ok,
         %FileStruct{
           path: path,
           handle: io_device,
           state: :open,
           backend: __MODULE__,
           metadata: %{mode: mode}
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec load(Comn.Repo.File.handle(), keyword()) ::
          {:ok, Comn.Repo.File.handle()} | {:error, term()}
  @impl Comn.Repo.File
  def load(fs, opts \\ [])

  def load(%FileStruct{state: :open, handle: handle, metadata: meta} = fs, _opts) do
    mode = Map.get(meta, :mode, [:read, :binary])

    if :write in mode and :read not in mode do
      {:ok, %{fs | buffer: nil, state: :loaded}}
    else
      case IO.read(handle, :eof) do
        data when is_binary(data) ->
          {:ok, %{fs | buffer: data, state: :loaded}}

        # an empty file reads as :eof, which is an empty buffer, not an error
        :eof ->
          {:ok, %{fs | buffer: "", state: :loaded}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  def load(%FileStruct{state: state}, _opts),
    do:
      {:error,
       ErrReg.error!("repo.file/invalid_state", message: "handle is #{state}, expected open")}

  @spec stream(Comn.Repo.File.handle(), keyword()) :: {:ok, Enumerable.t()} | {:error, term()}
  @impl Comn.Repo.File
  def stream(fs, opts \\ [])

  def stream(%FileStruct{state: :loaded, path: path}, _opts) do
    {:ok, File.stream!(path)}
  end

  def stream(%FileStruct{state: state}, _opts),
    do:
      {:error,
       ErrReg.error!("repo.file/invalid_state", message: "handle is #{state}, expected loaded")}

  @spec cast(Comn.Repo.File.handle(), keyword()) :: :ok | {:error, term()}
  @impl Comn.Repo.File
  def cast(fs, opts \\ [])

  def cast(%FileStruct{state: :loaded, path: path, buffer: buffer}, opts) do
    topic = Keyword.get(opts, :topic, "file:#{path}")
    Comn.EventBus.broadcast(topic, %{path: path, size: byte_size(buffer || "")})
    :ok
  end

  def cast(%FileStruct{state: state}, _opts),
    do:
      {:error,
       ErrReg.error!("repo.file/invalid_state", message: "handle is #{state}, expected loaded")}

  @spec read(Comn.Repo.File.handle(), keyword()) :: {:ok, binary()} | {:error, term()}
  @impl Comn.Repo.File
  def read(fs, opts \\ [])

  def read(%FileStruct{state: :loaded, buffer: buffer}, _opts) do
    {:ok, buffer}
  end

  def read(%FileStruct{state: state}, _opts),
    do:
      {:error,
       ErrReg.error!("repo.file/invalid_state", message: "handle is #{state}, expected loaded")}

  @spec write(Comn.Repo.File.handle(), iodata(), keyword()) ::
          {:ok, Comn.Repo.File.handle()} | {:error, term()}
  @impl Comn.Repo.File
  def write(fs, data, opts \\ [])

  def write(%FileStruct{state: :loaded, handle: handle} = fs, data, _opts) do
    :ok = IO.write(handle, data)
    {:ok, %{fs | buffer: data}}
  end

  def write(%FileStruct{state: state}, _data, _opts),
    do:
      {:error,
       ErrReg.error!("repo.file/invalid_state", message: "handle is #{state}, expected loaded")}

  @spec close(Comn.Repo.File.handle(), keyword()) :: :ok | {:error, term()}
  @impl Comn.Repo.File
  def close(fs, opts \\ [])

  def close(%FileStruct{state: state, handle: handle}, _opts)
      when state in [:open, :loaded] do
    File.close(handle)
  end

  def close(%FileStruct{state: state}, _opts),
    do:
      {:error,
       ErrReg.error!("repo.file/invalid_state",
         message: "handle is #{state}, expected open or loaded"
       )}

  # Comn.Repo callbacks

  @spec describe(Comn.Repo.resource()) :: {:ok, map()} | {:error, term()}
  @impl Comn.Repo
  def describe(%FileStruct{path: path, state: state, metadata: meta}) do
    case File.stat(path) do
      {:ok, stat} ->
        {:ok, Map.merge(meta, %{path: path, state: state, size: stat.size, type: stat.type})}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec get(Comn.Repo.resource(), keyword()) :: {:ok, term()} | {:error, term()}
  @impl Comn.Repo
  def get(%FileStruct{state: :loaded, path: path}, id: id) do
    path
    |> File.stream!()
    |> Stream.map(&Comn.Repo.decode_line/1)
    |> Enum.find(&match?(%Comn.Events.EventStruct{id: ^id}, &1))
    |> case do
      nil -> Comn.Repo.not_found(id)
      e -> {:ok, e}
    end
  end

  def get(%FileStruct{state: :loaded, buffer: buffer}, _opts), do: {:ok, buffer}

  def get(%FileStruct{state: state}, _opts),
    do:
      {:error,
       ErrReg.error!("repo.file/invalid_state", message: "handle is #{state}, expected loaded")}

  @spec set(Comn.Repo.resource(), keyword()) :: :ok | {:ok, term()} | {:error, term()}
  @impl Comn.Repo
  def set(%FileStruct{state: :loaded} = fs, [event: _] = opts) do
    # a file of events is a log: one encoded line per fact
    with {:ok, e} <- Comn.Repo.fetch_event(opts), do: write(fs, Comn.Repo.encode_line(e))
  end

  def set(%FileStruct{state: :loaded} = fs, opts) do
    data = Keyword.fetch!(opts, :value)
    write(fs, data)
  end

  def set(%FileStruct{state: state}, _opts),
    do:
      {:error,
       ErrReg.error!("repo.file/invalid_state", message: "handle is #{state}, expected loaded")}

  @spec delete(Comn.Repo.resource(), keyword()) :: :ok | {:ok, term()} | {:error, term()}
  @impl Comn.Repo
  def delete(%FileStruct{path: path}, _opts) do
    File.rm(path)
  end

  @spec observe(Comn.Repo.resource(), keyword()) :: Enumerable.t() | {:error, term()}
  @impl Comn.Repo
  def observe(%FileStruct{state: :loaded, path: path}, opts) do
    if Comn.Repo.events_view?(opts),
      do:
        path |> File.stream!() |> Stream.map(&Comn.Repo.decode_line/1) |> Stream.reject(&is_nil/1),
      else: File.stream!(path)
  end

  def observe(%FileStruct{state: state}, _opts),
    do:
      {:error,
       ErrReg.error!("repo.file/invalid_state", message: "handle is #{state}, expected loaded")}

  # Comn callbacks

  @spec look() :: String.t()
  @impl Comn
  def look, do: "File.Local — local filesystem file I/O with lifecycle state machine"

  @spec recon() :: map()
  @impl Comn
  def recon do
    %{
      backend: :local_fs,
      states: [:open, :loaded, :closed],
      persistence: :disk,
      type: :implementation
    }
  end

  @spec choices() :: map()
  @impl Comn
  def choices do
    %{mode: [":read", ":write", ":binary", ":append"]}
  end

  @spec act(map()) :: {:ok, term()} | {:error, term()}
  @impl Comn
  def act(%{action: :read, path: path}) do
    with {:ok, fs} <- open(path),
         {:ok, fs} <- load(fs),
         {:ok, data} <- read(fs) do
      close(fs)
      {:ok, data}
    end
  end

  def act(%{action: :write, path: path, data: data}) do
    with {:ok, fs} <- open(path, mode: [:write, :binary]),
         {:ok, fs} <- load(fs),
         {:ok, _fs} <- write(fs, data) do
      close(fs)
      {:ok, :written}
    end
  end

  def act(input), do: Comn.unknown_action(input)
end
