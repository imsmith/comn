defmodule Comn.Errors.ErrorStruct do
  @moduledoc """
  Standardized, machine-readable error struct.

  Context fields (`request_id`, `trace_id`, `correlation_id`) are populated
  automatically by `Comn.Errors.wrap/1` and `Comn.Errors.new/4` when the
  calling process has an ambient `Comn.Contexts` set.

  ## Examples

      iex> err = Comn.Errors.ErrorStruct.new("validation", "email", "bad format")
      iex> err.reason
      "validation"
  """

  @enforce_keys [:reason, :message]
  defstruct [
    :reason,
    :field,
    :message,
    :suggestion,
    :code,
    :request_id,
    :trace_id,
    :correlation_id
  ]

  @type t :: %__MODULE__{
          reason: String.t(),
          field: String.t() | nil,
          message: String.t(),
          suggestion: String.t() | nil,
          code: String.t() | nil,
          request_id: String.t() | nil,
          trace_id: String.t() | nil,
          correlation_id: String.t() | nil
        }

  @doc "Creates a new ErrorStruct. `reason` and `message` are required."
  @spec new(String.t(), String.t() | nil, String.t(), String.t() | nil) :: t()
  def new(reason, field, message, suggestion \\ nil) do
    %__MODULE__{
      reason: reason,
      field: field,
      message: message,
      suggestion: suggestion
    }
  end
end
