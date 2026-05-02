defmodule Comn.Discovery do
  @moduledoc """
  Runtime discovery of all modules implementing `@behaviour Comn`.

  Scans loaded modules for the four Comn callbacks (`look/0`, `recon/0`,
  `choices/0`, `act/1`) and indexes them by type, parent behaviour, and
  module name. Populated automatically at application boot via
  `Comn.Application`.

  ## Queries

      # Everything
      Comn.Discovery.all()
      #=> [Comn.Repo, Comn.Repo.Table.ETS, Comn.Events.NATS, ...]

      # By type
      Comn.Discovery.by_type(:behaviour)
      #=> [Comn.Repo, Comn.Events, Comn.Secrets, ...]

      Comn.Discovery.by_type(:implementation)
      #=> [Comn.Repo.Table.ETS, Comn.Repo.File.Local, ...]

      # Implementations of a specific behaviour
      Comn.Discovery.implementations_of(Comn.Repo.File)
      #=> [Comn.Repo.File.Local, Comn.Repo.File.NFS, Comn.Repo.File.IPFS]

      # Full metadata for a module
      Comn.Discovery.lookup(Comn.Repo.Table.ETS)
      #=> %{module: Comn.Repo.Table.ETS, look: "ETS — ...", type: :implementation, ...}

  ## Integration with Comn behaviour

  Discovery reads from `recon/0` on each module. Modules that return an
  `:extends` key in their recon map are indexed as implementations of that
  parent behaviour. Modules that list `:behaviours` in their Elixir module
  info are also checked.
  """

  @persistent_term_key :comn_discovery_index

  # All Comn modules that implement @behaviour Comn.
  # Listed here to ensure they are loaded before discovery scans
  # :code.all_loaded/0 — the BEAM only loads modules on first reference.
  @comn_modules [
    Comn.Repo,
    Comn.Repo.Table,
    Comn.Repo.Table.ETS,
    Comn.Repo.File,
    Comn.Repo.File.Local,
    Comn.Repo.File.NFS,
    Comn.Repo.File.IPFS,
    Comn.Repo.Graphs,
    Comn.Repo.Graphs.Graph,
    Comn.Repo.Cmd,
    Comn.Repo.Cmd.Shell,
    Comn.Repo.Batch,
    Comn.Repo.Batch.Mem,
    Comn.Repo.Queue,
    Comn.Repo.Queue.Mem,
    Comn.Repo.Queue.SQLite,
    Comn.Repo.Column,
    Comn.Repo.Column.ETS,
    Comn.Repo.Actor,
    Comn.Events,
    Comn.EventBus,
    Comn.EventLog,
    Comn.Events.NATS,
    Comn.Events.Registry,
    Comn.Errors,
    Comn.Contexts,
    Comn.Secrets,
    Comn.Secrets.Vault,
    Comn.Infra
  ]

  @doc """
  Returns all discovered Comn modules.
  """
  @spec all() :: [module()]
  def all do
    get_index()
    |> Map.keys()
    |> Enum.sort()
  end

  @doc """
  Returns modules matching a given type (`:behaviour`, `:implementation`, `:facade`).
  """
  @spec by_type(atom()) :: [module()]
  def by_type(type) when is_atom(type) do
    get_index()
    |> Enum.filter(fn {_mod, meta} -> meta.type == type end)
    |> Enum.map(fn {mod, _meta} -> mod end)
    |> Enum.sort()
  end

  @doc """
  Returns all implementation modules that extend a given behaviour.

  Checks both the `:extends` key from `recon/0` and Elixir's module
  `behaviours` attribute.
  """
  @spec implementations_of(module()) :: [module()]
  def implementations_of(behaviour) when is_atom(behaviour) do
    get_index()
    |> Enum.filter(fn {_mod, meta} -> behaviour in meta.extends end)
    |> Enum.map(fn {mod, _meta} -> mod end)
    |> Enum.sort()
  end

  @doc """
  Returns the full metadata map for a module, or `nil` if not discovered.
  """
  @spec lookup(module()) :: map() | nil
  def lookup(module) when is_atom(module) do
    get_index()[module]
  end

  @doc """
  Discovers all loaded modules implementing `@behaviour Comn` and indexes them.

  Ensures Comn's own modules are loaded first, then scans all loaded modules.
  Also picks up any consumer modules that implement `@behaviour Comn`.
  Called automatically by `Comn.Application` at boot.
  """
  @spec discover() :: :ok
  def discover do
    Enum.each(@comn_modules, &Code.ensure_loaded/1)

    index =
      for {module, _} <- :code.all_loaded(),
          comn_module?(module),
          into: %{} do
        {module, build_meta(module)}
      end

    :persistent_term.put(@persistent_term_key, index)
    :ok
  end

  @doc """
  Resets the discovery index. Useful in tests.
  """
  @spec reset() :: :ok
  def reset do
    :persistent_term.put(@persistent_term_key, %{})
    :ok
  end

  defp comn_module?(module) do
    function_exported?(module, :look, 0) and
      function_exported?(module, :recon, 0) and
      function_exported?(module, :choices, 0) and
      function_exported?(module, :act, 1)
  end

  defp build_meta(module) do
    recon = module.recon()

    extends = extract_extends(recon, module)
    type = Map.get(recon, :type) || Map.get(recon, :status) || :unknown

    %{
      module: module,
      look: module.look(),
      type: type,
      extends: extends,
      recon: recon,
      choices: module.choices()
    }
  end

  defp extract_extends(recon, module) do
    # From recon map — :extends can be a single module or a list
    from_recon =
      case Map.get(recon, :extends) do
        nil -> []
        list when is_list(list) -> list
        single -> [single]
      end

    # From Elixir module behaviours attribute
    from_behaviours =
      if function_exported?(module, :__info__, 1) do
        module.__info__(:attributes)
        |> Keyword.get_values(:behaviour)
        |> List.flatten()
        |> Enum.filter(&comn_module?/1)
      else
        []
      end

    Enum.uniq(from_recon ++ from_behaviours)
  end

  defp get_index do
    :persistent_term.get(@persistent_term_key, %{})
  end
end
