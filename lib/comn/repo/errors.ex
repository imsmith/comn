defmodule Comn.Repo.Errors do
  @moduledoc """
  Registered error codes for the `Comn.Repo` subsystem.
  """

  use Comn.Errors.Registry

  # Canonical event forms (ADR-0001), any shape
  register_error("repo/invalid_event", :validation,
    message: "Value under :event is not a Comn.Events.EventStruct"
  )

  register_error("repo/event_not_found", :persistence,
    message: "No event with that id in this resource"
  )

  # Table
  register_error("repo.table/not_found", :persistence, message: "Table or key does not exist")
  register_error("repo.table/already_exists", :persistence, message: "Table already exists")

  register_error("repo.table/invalid_opts", :validation,
    message: "Table backend options are missing or malformed"
  )

  register_error("repo.table/invalid_schema", :validation,
    message: "Not an Ecto schema module with a primary key"
  )

  register_error("repo.table/set_failed", :persistence, message: "The set saga rolled back")
  register_error("repo.table/delete_failed", :persistence, message: "The delete saga rolled back")

  # File
  register_error("repo.file/invalid_state", :validation,
    message: "File handle is not in the expected lifecycle state"
  )

  register_error("repo.file/stale_handle", :persistence,
    message: "NFS file handle is stale (ESTALE)"
  )

  register_error("repo.file/ipfs_error", :network, message: "IPFS daemon returned an error")

  # Graph
  register_error("repo.graph/missing_key", :validation,
    message: "Required :vertex or :key option was not provided"
  )

  register_error("repo.graph/unknown_query_type", :validation,
    message: "Unrecognized traversal query type"
  )

  register_error("repo.graph/zone_not_found", :persistence,
    message: "Zone locale does not correspond to a vertex in this graph"
  )

  register_error("repo.graph/unreachable", :persistence,
    message: "Target vertex is not reachable from the source zone"
  )

  # Batch
  register_error("repo.batch/buffer_full", :validation,
    message: "Batch buffer has reached its hard limit"
  )

  register_error("repo.batch/flush_failed", :persistence,
    message: "Failed to flush batch buffer to backend"
  )

  register_error("repo.batch/not_running", :persistence, message: "Batch process is not running")

  # Stream
  register_error("repo.stream/not_found", :persistence, message: "Stream does not exist")

  register_error("repo.stream/already_exists", :persistence,
    message: "Stream with this name already exists"
  )

  register_error("repo.stream/invalid_event", :validation,
    message: "Value is not a Comn.Events.EventStruct"
  )

  register_error("repo.stream/invalid_offset", :validation,
    message: "Offset is not valid for this stream"
  )

  register_error("repo.stream/append_only", :validation,
    message: "Streams are append-only; delete is not supported"
  )

  register_error("repo.stream/invalid_opts", :validation,
    message: "Stream backend options are missing or malformed"
  )

  register_error("repo.stream/backend_error", :network,
    message: "The stream backend returned an error"
  )

  # Bus
  register_error("repo.bus/invalid_opts", :validation,
    message: "Bus backend options are missing or malformed"
  )

  register_error("repo.bus/already_exists", :validation,
    message: "A bus with this name is already open"
  )

  register_error("repo.bus/invalid_event", :validation,
    message: "Value is not a Comn.Events.EventStruct"
  )

  register_error("repo.bus/not_retained", :validation,
    message: "A bus retains nothing; there is nothing to get or delete"
  )

  # Merkel
  register_error("repo.merkel/invalid_opts", :validation,
    message: "Merkel backend options are missing or malformed"
  )

  register_error("repo.merkel/already_exists", :validation,
    message: "A merkel with this name is already open"
  )

  register_error("repo.merkel/not_found", :persistence,
    message: "Merkel does not exist or is closed"
  )

  register_error("repo.merkel/unknown_address", :persistence, message: "No node at that address")

  register_error("repo.merkel/invalid_event", :validation,
    message: "Value could not be converted to a Comn.Events.EventStruct"
  )

  register_error("repo.merkel/immutable", :validation,
    message: "Merkel content is immutable; delete is not supported"
  )

  register_error("repo.merkel/tampered", :persistence,
    message: "Stored content no longer matches its address"
  )

  register_error("repo.merkel/backend_error", :network,
    message: "The merkel backend returned an error"
  )

  # Column
  register_error("repo.column/not_found", :persistence, message: "Column store does not exist")

  register_error("repo.column/invalid_schema", :validation,
    message: "Schema definition is invalid"
  )

  register_error("repo.column/schema_mismatch", :validation,
    message: "Row does not conform to the defined schema"
  )

  register_error("repo.column/unknown_column", :validation,
    message: "Query references a column not in the schema"
  )

  register_error("repo.column/flush_failed", :persistence,
    message: "Failed to flush write buffer to storage"
  )

  register_error("repo.column/query_failed", :persistence, message: "Projection query failed")
end
