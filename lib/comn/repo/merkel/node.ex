defmodule Comn.Repo.Merkel.Node do
  @moduledoc """
  One link of a merkel chain: what is stored and what is hashed.

  - `address` — this node's address: a hash over `parent` and
    `content_address`, so it commits to the whole chain behind it
  - `parent` — the previous node's address, `nil` at genesis
  - `content_address` — the hash of `content` alone
  - `content` — the canonical bytes (`Comn.Merkel.to_content/1`) of the fact
  - `algo` — the hash algorithm the backend used

  `Comn.Repo.Merkel.verify/1` recomputes both hashes for every node from
  root to genesis. Addresses are opaque per backend: the Mem backend uses
  sha256 hex, the Git backend uses git's own object ids.
  """

  @enforce_keys [:address, :parent, :content_address, :content, :algo]
  defstruct [:address, :parent, :content_address, :content, :algo]

  @type t :: %__MODULE__{
          address: String.t(),
          parent: String.t() | nil,
          content_address: String.t(),
          content: binary(),
          algo: atom()
        }
end
