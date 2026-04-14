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

  @behaviour Comn
  @behaviour Comn.Repo
  @behaviour Comn.Repo.File

  @default_api "http://localhost:5001"

  # Comn.Repo.File callbacks

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

      {:ok, %{status: status, body: body}} ->
        {:error, {:ipfs_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl Comn.Repo.File
  def load(fs, opts \\ [])

  def load(%FileStruct{state: :open, path: cid, metadata: %{api: api}} = fs, _opts) do
    case Req.post("#{api}/api/v0/cat", params: [arg: cid]) do
      {:ok, %{status: 200, body: data}} ->
        {:ok, %{fs | buffer: data, state: :loaded}}

      {:ok, %{status: status, body: body}} ->
        {:error, {:ipfs_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def load(%FileStruct{state: state}, _opts),
    do: {:error, {:invalid_state, state, :expected_open}}

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
    do: {:error, {:invalid_state, state, :expected_loaded}}

  @impl Comn.Repo.File
  def cast(fs, opts \\ [])

  def cast(%FileStruct{state: :loaded, path: cid, buffer: buffer, metadata: %{api: api}}, opts) do
    topic = Keyword.get(opts, :topic, "file:#{cid}")

    case Req.post("#{api}/api/v0/pubsub/pub",
           params: [arg: topic],
           body: buffer || ""
         ) do
      {:ok, %{status: 200}} -> :ok
      {:ok, %{status: status, body: body}} -> {:error, {:ipfs_error, status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  def cast(%FileStruct{state: state}, _opts),
    do: {:error, {:invalid_state, state, :expected_loaded}}

  @impl Comn.Repo.File
  def read(fs, opts \\ [])

  def read(%FileStruct{state: :loaded, buffer: buffer}, _opts) do
    {:ok, buffer}
  end

  def read(%FileStruct{state: state}, _opts),
    do: {:error, {:invalid_state, state, :expected_loaded}}

  @impl Comn.Repo.File
  def write(fs, data, opts \\ [])

  def write(%FileStruct{state: :loaded, metadata: %{api: api}} = fs, data, _opts) do
    case Req.post("#{api}/api/v0/add",
           body: data,
           headers: [{"content-type", "application/octet-stream"}]
         ) do
      {:ok, %{status: 200, body: %{"Hash" => new_cid}}} ->
        {:ok, %{fs | path: new_cid, buffer: data}}

      {:ok, %{status: status, body: body}} ->
        {:error, {:ipfs_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def write(%FileStruct{state: state}, _data, _opts),
    do: {:error, {:invalid_state, state, :expected_loaded}}

  @impl Comn.Repo.File
  def close(fs, opts \\ [])

  def close(%FileStruct{state: state}, _opts) when state in [:open, :loaded] do
    :ok
  end

  def close(%FileStruct{state: state}, _opts),
    do: {:error, {:invalid_state, state, :expected_open_or_loaded}}

  # Comn.Repo callbacks

  @impl Comn.Repo
  def describe(%FileStruct{path: cid, state: state, metadata: meta}) do
    {:ok, %{cid: cid, state: state, backend: __MODULE__, metadata: meta}}
  end

  @impl Comn.Repo
  def get(%FileStruct{state: :loaded, buffer: buffer}, _opts), do: {:ok, buffer}

  def get(%FileStruct{state: state}, _opts),
    do: {:error, {:invalid_state, state, :expected_loaded}}

  @impl Comn.Repo
  def set(%FileStruct{state: :loaded} = fs, opts) do
    data = Keyword.fetch!(opts, :value)
    write(fs, data)
  end

  def set(%FileStruct{state: state}, _opts),
    do: {:error, {:invalid_state, state, :expected_loaded}}

  @impl Comn.Repo
  def delete(%FileStruct{path: cid, metadata: %{api: api}}, _opts) do
    case Req.post("#{api}/api/v0/pin/rm", params: [arg: cid]) do
      {:ok, %{status: 200}} -> :ok
      {:ok, %{status: status, body: body}} -> {:error, {:ipfs_error, status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl Comn.Repo
  def observe(%FileStruct{state: :loaded, buffer: buffer}, _opts) do
    [buffer]
  end

  def observe(%FileStruct{state: state}, _opts),
    do: {:error, {:invalid_state, state, :expected_loaded}}

  # Comn callbacks

  @impl Comn
  def look, do: "File.IPFS — content-addressed file I/O via IPFS daemon HTTP API"

  @impl Comn
  def recon do
    %{
      backend: :ipfs,
      default_api: @default_api,
      content_addressed: true,
      type: :implementation
    }
  end

  @impl Comn
  def choices do
    %{api: "IPFS daemon endpoint (default: #{@default_api})"}
  end

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
