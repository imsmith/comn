defmodule Comn.Repo.File.Local do
  @moduledoc """
  Local filesystem implementation of Comn.Repo.File and Comn.Repo.
  """

  alias Comn.Repo.File.FileStruct

  @behaviour Comn.Repo
  @behaviour Comn.Repo.File

  # Comn.Repo.File callbacks

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

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  def load(%FileStruct{state: state}, _opts),
    do: {:error, {:invalid_state, state, :expected_open}}

  @impl Comn.Repo.File
  def stream(fs, opts \\ [])

  def stream(%FileStruct{state: :loaded, path: path}, _opts) do
    {:ok, File.stream!(path)}
  end

  def stream(%FileStruct{state: state}, _opts),
    do: {:error, {:invalid_state, state, :expected_loaded}}

  @impl Comn.Repo.File
  def cast(fs, opts \\ [])

  def cast(%FileStruct{state: :loaded, path: path, buffer: buffer}, opts) do
    topic = Keyword.get(opts, :topic, "file:#{path}")
    Comn.EventBus.broadcast(topic, %{path: path, size: byte_size(buffer || "")})
    :ok
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

  def write(%FileStruct{state: :loaded, handle: handle} = fs, data, _opts) do
    case IO.write(handle, data) do
      :ok -> {:ok, %{fs | buffer: data}}
      {:error, reason} -> {:error, reason}
    end
  end

  def write(%FileStruct{state: state}, _data, _opts),
    do: {:error, {:invalid_state, state, :expected_loaded}}

  @impl Comn.Repo.File
  def close(fs, opts \\ [])

  def close(%FileStruct{state: state, handle: handle}, _opts)
      when state in [:open, :loaded] do
    File.close(handle)
  end

  def close(%FileStruct{state: state}, _opts),
    do: {:error, {:invalid_state, state, :expected_open_or_loaded}}

  # Comn.Repo callbacks

  @impl Comn.Repo
  def describe(%FileStruct{path: path, state: state, metadata: meta}) do
    case File.stat(path) do
      {:ok, stat} ->
        {:ok, Map.merge(meta, %{path: path, state: state, size: stat.size, type: stat.type})}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl Comn.Repo
  def get(%FileStruct{state: :loaded, buffer: buffer}, _opts), do: {:ok, buffer}
  def get(%FileStruct{state: state}, _opts), do: {:error, {:invalid_state, state, :expected_loaded}}

  @impl Comn.Repo
  def set(%FileStruct{state: :loaded} = fs, opts) do
    data = Keyword.fetch!(opts, :value)
    write(fs, data)
  end

  def set(%FileStruct{state: state}, _opts),
    do: {:error, {:invalid_state, state, :expected_loaded}}

  @impl Comn.Repo
  def delete(%FileStruct{path: path}, _opts) do
    File.rm(path)
  end

  @impl Comn.Repo
  def observe(%FileStruct{state: :loaded, path: path}, _opts) do
    File.stream!(path)
  end

  def observe(%FileStruct{state: state}, _opts),
    do: {:error, {:invalid_state, state, :expected_loaded}}
end
