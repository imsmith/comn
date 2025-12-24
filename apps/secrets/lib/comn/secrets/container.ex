defmodule Comn.Secrets.Container do
  @moduledoc """
  Collection of locked blobs.

  A Container is used to group multiple LockedBlobs together, allowing
  them to be stored, transferred, or managed as a single unit.

  ## Fields

  - `id` - Container identifier (UUID v4)
  - `blobs` - List of LockedBlob structs
  - `metadata` - Arbitrary metadata about the container
  """

  alias Comn.Secrets.LockedBlob

  @type t :: %__MODULE__{
          id: String.t() | nil,
          blobs: [LockedBlob.t()],
          metadata: map()
        }

  defstruct [
    :id,
    blobs: [],
    metadata: %{}
  ]
end
