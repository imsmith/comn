defmodule Comn.Repo.File.FileStruct do
  @moduledoc """
  Struct representing a file handle with lifecycle state.

  States: `:init`, `:open`, `:loaded`, `:closed`
  """

  @type t :: %__MODULE__{
          path: String.t() | nil,
          handle: :file.io_device() | nil,
          state: :init | :open | :loaded | :closed,
          backend: module(),
          metadata: map(),
          buffer: binary() | nil
        }

  @enforce_keys [:backend]
  defstruct path: nil,
            handle: nil,
            state: :init,
            backend: nil,
            metadata: %{},
            buffer: nil
end
