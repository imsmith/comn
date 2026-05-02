defmodule Comn.Repo.Queue.Errors do
  @moduledoc """
  Registered error codes for `Comn.Repo.Queue`.

  All codes share the `repo.queue/` prefix.
  """

  use Comn.Errors.Registry

  register_error "repo.queue/open_failed", :persistence, message: "Queue could not be opened (backend rejected the open)"
  register_error "repo.queue/corrupt", :persistence, message: "Queue storage is corrupt or unreadable"
  register_error "repo.queue/item_not_found", :validation, message: "No item in the queue matched the predicate"
  register_error "repo.queue/invalid_opts", :validation, message: "open/2 received invalid options (e.g. unknown :backend, missing :path)"
  register_error "repo.queue/reserve_failed", :persistence, message: "Backend reserve operation failed"
  register_error "repo.queue/serialization_failed", :validation, message: "Item could not be serialized to the backend's storage format"
end
