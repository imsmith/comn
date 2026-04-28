defmodule Comn.Repo.Errors do
  @moduledoc """
  Registered error codes for the `Comn.Repo` subsystem.
  """

  use Comn.Errors.Registry

  # Table
  register_error "repo.table/not_found",      :persistence, message: "Table or key does not exist"
  register_error "repo.table/already_exists",  :persistence, message: "Table already exists"

  # File
  register_error "repo.file/invalid_state",   :validation,  message: "File handle is not in the expected lifecycle state"
  register_error "repo.file/stale_handle",    :persistence, message: "NFS file handle is stale (ESTALE)"
  register_error "repo.file/ipfs_error",      :network,     message: "IPFS daemon returned an error"

  # Graph
  register_error "repo.graph/missing_key",        :validation,  message: "Required :vertex or :key option was not provided"
  register_error "repo.graph/unknown_query_type",  :validation, message: "Unrecognized traversal query type"
  register_error "repo.graph/zone_not_found",      :persistence, message: "Zone locale does not correspond to a vertex in this graph"
  register_error "repo.graph/unreachable",         :persistence, message: "Target vertex is not reachable from the source zone"

  # Batch
  register_error "repo.batch/buffer_full",  :validation,  message: "Batch buffer has reached its hard limit"
  register_error "repo.batch/flush_failed", :persistence, message: "Failed to flush batch buffer to backend"
  register_error "repo.batch/not_running",  :persistence, message: "Batch process is not running"

  # Column
  register_error "repo.column/not_found",       :persistence, message: "Column store does not exist"
  register_error "repo.column/invalid_schema",  :validation,  message: "Schema definition is invalid"
  register_error "repo.column/schema_mismatch", :validation,  message: "Row does not conform to the defined schema"
  register_error "repo.column/unknown_column",  :validation,  message: "Query references a column not in the schema"
  register_error "repo.column/flush_failed",    :persistence, message: "Failed to flush write buffer to storage"
  register_error "repo.column/query_failed",    :persistence, message: "Projection query failed"
end
