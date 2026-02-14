defmodule Comn.Repo do
  @moduledoc """
  A Repo is an Application Delivery Controller for your Internal Procedure Calls.

  It creates internally common I/O behavior for data repositories while accommodating modularity to external providers.

  Each implementing module (e.g., Comn.Repo.Cmd, Comn.Repo.Table) must
  conform to this interface, whether the external provider is a shell, queue, table, or graph.
  """

  @callback describe(term()) :: {:ok, map()} | {:error, term()}
  @callback get(term(), keyword()) :: {:ok, term()} | {:error, term()}
  @callback set(term(), keyword()) :: :ok | {:ok, term()} | {:error, term()}
  @callback delete(term(), keyword()) :: :ok | {:ok, term()} | {:error, term()}
  @callback observe(term(), keyword()) :: Enumerable.t() | {:error, term()}
end
