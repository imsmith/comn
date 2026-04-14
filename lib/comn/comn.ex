defmodule Comn do
  @moduledoc """
  Universal introspection and action protocol for every module in the system.

  The four callbacks — `look`, `recon`, `choices`, `act` — form a discovery
  loop drawn from the Anemos design:

  1. **look** — what is this? (human-readable summary)
  2. **recon** — what can it do? (machine-readable metadata)
  3. **choices** — what are my options? (inputs, adapters, modes)
  4. **act** — do it (execute with a map of inputs)

  Every module that declares `@behaviour Comn` implements all four.
  Behaviour modules (e.g. `Comn.Repo`, `Comn.Events`) describe their
  contract; implementation modules (e.g. `Comn.Repo.Table.ETS`,
  `Comn.Events.NATS`) describe their concrete capabilities.

  ## Examples

      iex> Comn.Repo.look()
      "Repo — common I/O behaviour for data repositories (tables, files, graphs, commands)"

      iex> %{type: :behaviour} = Comn.Events.recon()

      iex> %{implementations: ["ETS"]} = Comn.Repo.Table.choices()

  Behaviour-only modules return `{:error, :behaviour_only}` from `act/1`:

      iex> Comn.Repo.act(%{})
      {:error, :behaviour_only}
  """

  @doc """
  Human-readable summary of what this module is and what it does.

  Returns a plain string suitable for display in a TUI, CLI, or log.

  ## Examples

      iex> Comn.Errors.look()
      "Errors — wrap, categorize, and create structured errors"
  """
  @callback look() :: String.t()

  @doc """
  Technical introspection — inputs, outputs, capabilities, runtime metadata.

  Returns a map describing the module's structural and operational properties:
  type signatures, required capabilities, expected latency, idempotency,
  composability, and any other machine-useful metadata. Always includes a
  `:type` key (`:behaviour`, `:implementation`, or `:facade`).

  ## Examples

      iex> %{callbacks: callbacks, type: :behaviour} = Comn.Repo.recon()
      iex> :get in callbacks
      true
  """
  @callback recon() :: map()

  @doc """
  Explorable inputs and selectable options available from this module.

  Returns a map of option names to their possible values or constraints.
  Drives interactive selection in TUI/CLI and programmatic discovery by
  orchestration layers.

  ## Examples

      iex> %{adapters: adapters} = Comn.Events.choices()
      iex> "NATS" in adapters
      true
  """
  @callback choices() :: map()

  @doc """
  Execute the module's primary action.

  Takes a map of inputs (as informed by `choices/0` and `recon/0`) and
  performs the module's work. Returns `{:ok, result}` or `{:error, reason}`.

  Behaviour-only modules return `{:error, :behaviour_only}`.
  Unimplemented modules return `{:error, :not_implemented}`.
  """
  @callback act(map()) :: {:ok, term()} | {:error, term()}
end
