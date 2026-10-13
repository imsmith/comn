defmodule Comn.Errors.Core do
  @moduledoc """
  Registered error codes for the `Comn` behaviour itself.

  These back the `act/1` fallbacks every `Comn` module shares; see
  `Comn.behaviour_only/0`, `Comn.not_implemented/0`, and
  `Comn.unknown_action/1`.
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
end
