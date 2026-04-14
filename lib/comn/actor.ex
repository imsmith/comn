defmodule Comn.Repo.Actor do
  @moduledoc """
  Actor-style repo for tasks, API calls, and agent communication.

  Future implementation of `Comn.Repo` for operations that involve
  long-running processes, external API calls, or inter-agent messaging.
  Not yet implemented.

  Implements `@behaviour Comn` for uniform introspection.

  ## Examples

      iex> Comn.Repo.Actor.act(%{})
      {:error, :not_implemented}
  """

  @behaviour Comn

  @impl Comn
  def look, do: "Repo.Actor — actor-style repo for tasks, API calls, agent communication (not yet implemented)"

  @impl Comn
  def recon do
    %{status: :not_implemented, extends: Comn.Repo, type: :implementation}
  end

  @impl Comn
  def choices, do: %{}

  @impl Comn
  def act(_input), do: {:error, :not_implemented}
end
