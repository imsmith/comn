defmodule Comn.Errors.Core do
  @moduledoc """
  Registered error codes for Comn's core: the `Comn` behaviour's shared
  `act/1` fallbacks, the `Comn.Error` protocol, the error registry itself,
  and `Comn.Zone`.

  See `Comn.behaviour_only/0`, `Comn.not_implemented/0`, and
  `Comn.unknown_action/1` for the `comn/*` codes.
  """

  use Comn.Errors.Registry

  register_error "comn/behaviour_only", :validation,
    message: "Module is a behaviour; call act/1 on an implementation",
    suggestion: "Pick an implementation from choices/0"

  register_error "comn/not_implemented", :internal,
    message: "Module is a placeholder; act/1 is not implemented yet"

  register_error "comn/unknown_action", :validation,
    message: "Unrecognised action for this module",
    suggestion: "See choices/0 for the supported actions"

  # Comn.Error protocol
  register_error "errors/invalid_tuple", :validation,
    message: "Tuple must be {reason, field, message, suggestion}"

  register_error "errors/missing_keys", :validation,
    message: "Map must have :reason and :message keys"

  # Comn.Errors.Registry
  register_error "errors/unknown_code", :validation,
    message: "Error code is not registered",
    suggestion: "Register it with register_error/3 or check Comn.Errors.Registry.codes/0"

  register_error "errors/duplicate_code", :internal,
    message: "Error code is already registered by another module"

  register_error "errors/not_a_registry_module", :validation,
    message: "Module was not compiled with `use Comn.Errors.Registry`"

  # Comn.Zone
  register_error "zone/empty", :validation,
    message: "Zone string is empty"

  register_error "zone/unknown_realm", :validation,
    message: "Realm is not one of the known realms",
    suggestion: "Use one of: local, mesh, cluster, region, global"
end
