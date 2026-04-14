defmodule Comn.Repo.Cmd do
  @moduledoc """
  Behaviour for command execution with a full lifecycle verb set.

  Extends `Comn.Repo` with operational verbs: `validate`, `apply`, `reset`,
  `enable`, `disable`, `sync`, `status`, `test`, `invoke`, `info`, `watch`,
  `run`, and `probe`. Implementations wrap shell commands, config management
  tools, or any imperative side-effecting operation.

  Also implements `@behaviour Comn` for uniform introspection.

  ## Examples

      iex> Comn.Repo.Cmd.look()
      "Cmd — behaviour for command execution with lifecycle verbs (validate, apply, reset, enable, disable, sync, run)"

      iex> %{callbacks: cbs} = Comn.Repo.Cmd.recon()
      iex> :validate in cbs
      true
  """

  @behaviour Comn

  @callback validate(term(), keyword()) :: :ok | {:error, term()}
  @callback apply(term(), keyword()) :: :ok | {:error, term()}
  @callback reset(term(), keyword()) :: :ok | {:error, term()}
  @callback enable(term(), keyword()) :: :ok | {:error, term()}
  @callback disable(term(), keyword()) :: :ok | {:error, term()}
  @callback sync(term(), keyword()) :: :ok | {:error, term()}
  @callback status(term(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback test(term(), keyword()) :: :ok | {:error, term()}
  @callback invoke(term(), keyword()) :: :ok | {:error, term()}
  @callback info(term()) :: {:ok, map()} | {:error, term()}
  @callback watch(term(), keyword()) :: Enumerable.t() | {:error, term()}
  @callback run(term(), keyword()) :: :ok | {:error, term()}
  @callback probe(term(), keyword()) :: :ok | {:error, term()}

  @impl Comn
  def look, do: "Cmd — behaviour for command execution with lifecycle verbs (validate, apply, reset, enable, disable, sync, run)"

  @impl Comn
  def recon do
    %{
      callbacks: [:validate, :apply, :reset, :enable, :disable, :sync, :status, :test, :invoke, :info, :watch, :run, :probe],
      type: :behaviour
    }
  end

  @impl Comn
  def choices do
    %{
      verbs: ["validate", "apply", "reset", "enable", "disable", "sync", "status", "test", "invoke", "info", "watch", "run", "probe"]
    }
  end

  @impl Comn
  def act(_input), do: {:error, :behaviour_only}
end
