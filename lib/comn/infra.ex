defmodule Comn.Infra do
  @moduledoc """
  Placeholder behaviour for infrastructure management.

  Not yet implemented. Will cover compute, storage, connectivity, and
  platform-specific backends (Proxmox, Unifi, etc.).

  Implements `@behaviour Comn` for uniform introspection.

  ## Examples

      iex> Comn.Infra.look()
      "Infra — placeholder for infrastructure management (not yet implemented)"

      iex> Comn.Infra.act(%{})
      {:error, :not_implemented}
  """

  @behaviour Comn

  @impl Comn
  def look, do: "Infra — placeholder for infrastructure management (not yet implemented)"

  @impl Comn
  def recon do
    %{status: :not_implemented, type: :behaviour}
  end

  @impl Comn
  def choices, do: %{}

  @impl Comn
  def act(_input), do: {:error, :not_implemented}
end
