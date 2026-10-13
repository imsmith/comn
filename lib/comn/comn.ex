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

  Behaviour-only modules return a registered `comn/behaviour_only` error
  from `act/1`:

      iex> {:error, %Comn.Errors.ErrorStruct{code: "comn/behaviour_only"}} = Comn.Repo.act(%{})
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

  Errors are always a `Comn.Errors.ErrorStruct`. Three codes are shared by
  every module and have helpers here: behaviour-only modules return
  `behaviour_only/0`, placeholders return `not_implemented/0`, and any
  implementation's fallback clause returns `unknown_action/1`.
  """
  @callback act(map()) :: {:ok, term()} | {:error, Comn.Errors.ErrorStruct.t()}

  alias Comn.Errors.ErrorStruct
  alias Comn.Errors.Registry

  @doc "`act/1` result for a behaviour-only module (`comn/behaviour_only`)."
  @spec behaviour_only() :: {:error, ErrorStruct.t()}
  def behaviour_only, do: {:error, Registry.error!("comn/behaviour_only")}

  @doc "`act/1` result for a placeholder module (`comn/not_implemented`)."
  @spec not_implemented() :: {:error, ErrorStruct.t()}
  def not_implemented, do: {:error, Registry.error!("comn/not_implemented")}

  @doc """
  `act/1` fallback for an unrecognised input (`comn/unknown_action`).

  The `:action` key of the input, if any, is recorded in `field`.

      iex> {:error, %Comn.Errors.ErrorStruct{code: "comn/unknown_action", field: ":bogus"}} =
      ...>   Comn.unknown_action(%{action: :bogus})
  """
  @spec unknown_action(term()) :: {:error, ErrorStruct.t()}
  def unknown_action(input) do
    field = if is_map(input) and Map.has_key?(input, :action), do: inspect(input.action)
    {:error, Registry.error!("comn/unknown_action", field: field)}
  end
end
