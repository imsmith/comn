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

  @typedoc "The command target — a service name, config path, or reference map."
  @type target :: atom() | String.t() | map()

  @doc """
  Checks whether the command and its inputs are valid before execution.

  Errors: implementation-specific validation failures.
  """
  @callback validate(target(), keyword()) :: :ok | {:error, term()}

  @doc """
  Executes the command's primary effect (create, configure, deploy, etc.).

  Errors: OS-level errors, permission failures, target unreachable.
  """
  @callback apply(target(), keyword()) :: :ok | {:error, term()}

  @doc """
  Reverts the command's effect, restoring the previous state.

  Errors: `:no_previous_state`, OS-level errors.
  """
  @callback reset(target(), keyword()) :: :ok | {:error, term()}

  @doc """
  Activates a previously disabled command or resource.

  Errors: `:already_enabled`, target not found.
  """
  @callback enable(target(), keyword()) :: :ok | {:error, term()}

  @doc """
  Deactivates a command or resource without destroying it.

  Errors: `:already_disabled`, target not found.
  """
  @callback disable(target(), keyword()) :: :ok | {:error, term()}

  @doc """
  Reconciles local state with a remote or canonical source.

  Errors: `:sync_conflict`, network/connection errors.
  """
  @callback sync(target(), keyword()) :: :ok | {:error, term()}

  @doc """
  Returns the current operational status as a map.

  Errors: target not found, unreachable.
  """
  @callback status(target(), keyword()) :: {:ok, map()} | {:error, term()}

  @doc """
  Runs a non-destructive check to verify the command works correctly.

  Errors: `:test_failed` with diagnostic details.
  """
  @callback test(target(), keyword()) :: :ok | {:error, term()}

  @doc """
  Triggers the command with explicit arguments (one-shot execution).

  Errors: same as `apply/2` — OS-level, permission, unreachable.
  """
  @callback invoke(target(), keyword()) :: :ok | {:error, term()}

  @doc """
  Returns static metadata about the command (name, version, capabilities).

  Errors: target not found.
  """
  @callback info(target()) :: {:ok, map()} | {:error, term()}

  @doc """
  Returns a stream of state changes or output for long-running observation.

  Errors: target not found, `:not_observable`.
  """
  @callback watch(target(), keyword()) :: Enumerable.t() | {:error, term()}

  @doc """
  Executes the command in the foreground, blocking until complete.

  Errors: non-zero exit codes, timeouts, OS-level errors.
  """
  @callback run(target(), keyword()) :: :ok | {:error, term()}

  @doc """
  Lightweight health or reachability check (is the target alive?).

  Errors: `:unreachable`, `:timeout`.
  """
  @callback probe(target(), keyword()) :: :ok | {:error, term()}

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
