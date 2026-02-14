defmodule Comn.Contexts.RuleStruct do
  @moduledoc "Concrete rule struct for defining business rules."

  defstruct [
    :name,
    :condition,
    :action,
    :priority,
    metadata: %{}
  ]

  @type t :: %__MODULE__{
          name: String.t() | nil,
          condition: term(),
          action: term(),
          priority: integer() | nil,
          metadata: map()
        }
end
