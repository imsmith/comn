defmodule Comn.Contexts.PolicyStruct do
  @moduledoc "Concrete policy struct for defining business policies. A policy is a named set of rules."

  defstruct [
    :name,
    :description,
    rules: [],
    metadata: %{}
  ]

  @type t :: %__MODULE__{
          name: String.t() | nil,
          description: String.t() | nil,
          rules: [Comn.Contexts.RuleStruct.t()],
          metadata: map()
        }
end
