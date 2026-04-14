defmodule Comn.Repo.Cmd.Shell do
  @moduledoc """
  Shell command execution backend for `Comn.Repo.Cmd`.

  Will implement the full `Comn.Repo` + `Comn.Repo.Cmd` verb set against
  OS-level shell commands. Not yet implemented.

  Implements `@behaviour Comn` for uniform introspection.

  ## Examples

      iex> Comn.Repo.Cmd.Shell.act(%{})
      {:error, :not_implemented}
  """

  @behaviour Comn

  @impl Comn
  def look, do: "Cmd.Shell — shell command execution (not yet implemented)"

  @impl Comn
  def recon do
    %{status: :not_implemented, extends: [Comn.Repo, Comn.Repo.Cmd], type: :implementation}
  end

  @impl Comn
  def choices, do: %{}

  @impl Comn
  def act(_input), do: {:error, :not_implemented}
end
