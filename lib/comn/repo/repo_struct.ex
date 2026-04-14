defmodule Comn.RepoStruct do
  @moduledoc "Base struct for repo resource metadata."

  @enforce_keys [:type]
  defstruct [:id, :name, :type, :data]
end
