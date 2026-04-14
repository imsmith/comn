defmodule Comn.Repo.File.IPFS do
  @moduledoc """
  IPFS daemon API backend for `Comn.Repo.File`.

  Content-addressed file I/O through a local IPFS daemon's HTTP API
  (default `http://localhost:5001`). Writes return a new CID; reads
  fetch by CID.

  Implements `@behaviour Comn` for uniform introspection.

  ## Examples

      iex> Comn.Repo.File.IPFS.look()
      "File.IPFS — content-addressed file I/O via IPFS daemon HTTP API"

      iex> %{content_addressed: true} = Comn.Repo.File.IPFS.recon()
  """

  alias Comn.Repo.File.FileStruct
  alias Comn.Errors.Registry, as: ErrReg

  @behaviour Comn
  @behaviour Comn.Repo
  @behaviour Comn.Repo.File

  @default_api "http://localhost:5001"

  # Comn.Repo.File callbacks

  @spec open(term(), keyword()) :: {:ok, Comn.Repo.File.handle()} | {:error, term()}
  @impl Comn.Repo.File
  def open(cid, opts \\ []) do
    api = Keyword.get(opts, :api, @default_api)

    case Req.post("#{api}/api/v0/files/stat", params: [arg: cid]) do
      {:ok, %{status: 200, body: body}} ->
        {:ok,
         %FileStruct{
           path: cid,
           handle: nil,
           state: :open,
           backend: __MODULE__,
           metadata: %{api: api, stat: body}
         }}

      {:ok, %{status: status, body: _body}} ->
        {:error, ErrReg.error!("repo.file/ipfs_error", message: "IPFS returned #{status}")}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec load(Comn.Repo.File.handle(), keyword()) :: {:ok, Comn.Repo.File.handle()} | {:error, term()}
  @impl Comn.Repo.File
  def load(fs, opts \\ [])

  def load(%FileStruct{state: :open, path: cid, metadata: %{api: api}} = fs, _opts) do
    case Req.post("#{api}/api/v0/cat", params: [arg: cid]) do
      {:ok, %{status: 200, body: data}} ->
        {:ok, %{fs | buffer: data, state: :loaded}}

      {:ok, %{status: status, body: _body}} ->
        {:error, ErrReg.error!("repo.file/ipfs_error", message: "IPFS returned #{status}")}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def load(%FileStruct{state: state}, _opts),
    do: {:error, ErrReg.error!("repo.file/invalid_state", message: "handle is #{state}, expected open")}

  @spec stream(Comn.Repo.File.handle(), keyword()) :: {:ok, Enumerable.t()} | {:error, term()}
  @impl Comn.Repo.File
  def stream(fs, opts \\ [])

  def stream(%FileStruct{state: :loaded, path: cid, metadata: %{api: api}}, _opts) do
    stream =
      Stream.resource(
        fn -> Req.post!("#{api}/api/v0/cat", params: [arg: cid], into: :self) end,
        fn req ->
          receive do
            {ref, {:data, data}} when ref == req.body ->
              {[data], req}

            {ref, :done} when ref == req.body ->
              {:halt, req}
          after
            30_000 -> {:halt, req}
          end
        end,
        fn _req -> :ok end
      )

    {:ok, stream}
  end

  def stream(%FileStruct{state: state}, _opts),
    do: {:error, ErrReg.error!("repo.file/invalid_state", message: "handle is #{state}, expected loaded")}

  @spec cast(Comn.Repo.File.handle(), keyword()) :: :ok | {:error, term()}
  @impl Comn.Repo.File
  def cast(fs, opts \\ [])

  def cast(%FileStruct{state: :loaded, path: cid, buffer: buffer, metadata: %{api: api}}, opts) do
    topic = Keyword.get(opts, :topic, "file:#{cid}")

    case Req.post("#{api}/api/v0/pubsub/pub",
           params: [arg: topic],
           body: buffer || ""
         ) do
      {:ok, %{status: 200}} -> :ok
      {:ok, %{status: status, body: _body}} -> {:error, ErrReg.error!("repo.file/ipfs_error", message: "IPFS returned #{status}")}
      {:error, reason} -> {:error, reason}
    end
  end

  def cast(%FileStruct{state: state}, _opts),
    do: {:error, ErrReg.error!("repo.file/invalid_state", message: "handle is #{state}, expected loaded")}

  @spec read(Comn.Repo.File.handle(), keyword()) :: {:ok, binary()} | {:error, term()}
  @impl Comn.Repo.File
  def read(fs, opts \\ [])

  def read(%FileStruct{state: :loaded, buffer: buffer}, _opts) do
    {:ok, buffer}
  end

  def read(%FileStruct{state: state}, _opts),
    do: {:error, ErrReg.error!("repo.file/invalid_state", message: "handle is #{state}, expected loaded")}

  @spec write(Comn.Repo.File.handle(), iodata(), keyword()) :: {:ok, Comn.Repo.File.handle()} | {:error, term()}
  @impl Comn.Repo.File
  def write(fs, data, opts \\ [])

  def write(%FileStruct{state: :loaded, metadata: %{api: api}} = fs, data, _opts) do
    case Req.post("#{api}/api/v0/add",
           body: data,
           headers: [{"content-type", "application/octet-stream"}]
         ) do
      {:ok, %{status: 200, body: %{"Hash" => new_cid}}} ->
        {:ok, %{fs | path: new_cid, buffer: data}}

      {:ok, %{status: status, body: _body}} ->
        {:error, ErrReg.error!("repo.file/ipfs_error", message: "IPFS returned #{status}")}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def write(%FileStruct{state: state}, _data, _opts),
    do: {:error, ErrReg.error!("repo.file/invalid_state", message: "handle is #{state}, expected loaded")}

  @spec close(Comn.Repo.File.handle(), keyword()) :: :ok | {:error, term()}
  @impl Comn.Repo.File
  def close(fs, opts \\ [])

  def close(%FileStruct{state: state}, _opts) when state in [:open, :loaded] do
    :ok
  end

  def close(%FileStruct{state: state}, _opts),
    do: {:error, ErrReg.error!("repo.file/invalid_state", message: "handle is #{state}, expected open or loaded")}

  # Comn.Repo callbacks

  @spec describe(Comn.Repo.resource()) :: {:ok, map()} | {:error, term()}
  @impl Comn.Repo
  def describe(%FileStruct{path: cid, state: state, metadata: meta}) do
    {:ok, %{cid: cid, state: state, backend: __MODULE__, metadata: meta}}
  end

  @spec get(Comn.Repo.resource(), keyword()) :: {:ok, term()} | {:error, term()}
  @impl Comn.Repo
  def get(%FileStruct{state: :loaded, buffer: buffer}, _opts), do: {:ok, buffer}

  def get(%FileStruct{state: state}, _opts),
    do: {:error, ErrReg.error!("repo.file/invalid_state", message: "handle is #{state}, expected loaded")}

  @spec set(Comn.Repo.resource(), keyword()) :: :ok | {:ok, term()} | {:error, term()}
  @impl Comn.Repo
  def set(%FileStruct{state: :loaded} = fs, opts) do
    data = Keyword.fetch!(opts, :value)
    write(fs, data)
  end

  def set(%FileStruct{state: state}, _opts),
    do: {:error, ErrReg.error!("repo.file/invalid_state", message: "handle is #{state}, expected loaded")}

  @spec delete(Comn.Repo.resource(), keyword()) :: :ok | {:ok, term()} | {:error, term()}
  @impl Comn.Repo
  def delete(%FileStruct{path: cid, metadata: %{api: api}}, _opts) do
    case Req.post("#{api}/api/v0/pin/rm", params: [arg: cid]) do
      {:ok, %{status: 200}} -> :ok
      {:ok, %{status: status, body: _body}} -> {:error, ErrReg.error!("repo.file/ipfs_error", message: "IPFS returned #{status}")}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec observe(Comn.Repo.resource(), keyword()) :: Enumerable.t() | {:error, term()}
  @impl Comn.Repo
  def observe(%FileStruct{state: :loaded, buffer: buffer}, _opts) do
    [buffer]
  end

  def observe(%FileStruct{state: state}, _opts),
    do: {:error, ErrReg.error!("repo.file/invalid_state", message: "handle is #{state}, expected loaded")}

  # Comn callbacks

  @spec look() :: String.t()
  @impl Comn
  def look, do: "File.IPFS — content-addressed file I/O via IPFS daemon HTTP API"

  @spec recon() :: map()
  @impl Comn
  def recon do
    %{
      backend: :ipfs,
      default_api: @default_api,
      content_addressed: true,
      type: :implementation
    }
  end

  @spec choices() :: map()
  @impl Comn
  def choices do
    %{api: "IPFS daemon endpoint (default: #{@default_api})"}
  end

  @spec act(map()) :: {:ok, term()} | {:error, term()}
  @impl Comn
  def act(%{action: :read, cid: cid} = input) do
    api = Map.get(input, :api, @default_api)

    with {:ok, fs} <- open(cid, api: api),
         {:ok, fs} <- load(fs),
         {:ok, data} <- read(fs) do
      close(fs)
      {:ok, data}
    end
  end

  def act(%{action: :write, data: data} = input) do
    api = Map.get(input, :api, @default_api)

    with {:ok, fs} <- open("new", api: api),
         {:ok, fs} <- load(fs),
         {:ok, fs} <- write(fs, data) do
      close(fs)
      {:ok, fs.path}
    end
  end

  def act(_input), do: {:error, :unknown_action}
end
