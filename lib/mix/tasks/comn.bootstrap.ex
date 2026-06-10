defmodule Mix.Tasks.Comn.Bootstrap do
  @shortdoc "Wire comn (and busybody) into this Phoenix app in one shot"
  @moduledoc """
  Combined installer. Adds the comn and busybody path deps, then composes
  their installers.

  Path-dep oriented: it wires comn and busybody as local sibling path deps.
  For a git-dep install, use the individual installers (`mix comn.install
  --git ...` / `mix busybody.install --git ...`) instead.

      mix comn.bootstrap

  ## Options

    * `--no-busybody`       - install comn only
    * `--comn-path`         - comn path dep source (default `../comn`)
    * `--busybody-path`     - busybody path dep source (default `../busybody`)
    * `--name`              - app name (passed through)
    * `--no-context-plug`   - passed through to comn.install
    * `--no-error-registry` - passed through to comn.install
  """

  use Igniter.Mix.Task

  @impl Igniter.Mix.Task
  def info(_argv, _composing_task) do
    %Igniter.Mix.Task.Info{
      group: :comn,
      example: "mix comn.bootstrap",
      composes: ["comn.install", "busybody.install"],
      schema: [
        busybody: :boolean,
        comn_path: :string,
        busybody_path: :string,
        name: :string,
        context_plug: :boolean,
        error_registry: :boolean
      ],
      defaults: [busybody: true]
    }
  end

  @impl Igniter.Mix.Task
  def igniter(igniter) do
    opts = igniter.args.options

    igniter
    |> Igniter.compose_task("comn.install", comn_argv(opts))
    |> maybe_busybody(opts)
    |> Igniter.add_notice("""
    Bootstrap complete. Run `mix deps.get`, then start your app and busybody.
    If the installers could not run (deps not yet compiled), run
    `mix deps.get` and re-run `mix comn.bootstrap`.
    """)
  end

  defp maybe_busybody(igniter, opts) do
    if opts[:busybody] == false do
      igniter
    else
      igniter =
        Igniter.Project.Deps.add_dep(
          igniter,
          {:busybody, path: opts[:busybody_path] || "../busybody", only: :dev}
        )

      if Code.ensure_loaded?(Mix.Tasks.Busybody.Install) do
        Igniter.compose_task(igniter, "busybody.install", busybody_argv(opts))
      else
        Igniter.add_warning(
          igniter,
          "busybody.install not loadable yet; added the dep only. Run `mix deps.get` then `mix busybody.install`."
        )
      end
    end
  end

  defp comn_argv(opts) do
    []
    |> put_flag("--path", opts[:comn_path])
    |> put_flag("--name", opts[:name])
    |> put_switch("--no-context-plug", opts[:context_plug] == false)
    |> put_switch("--no-error-registry", opts[:error_registry] == false)
  end

  defp busybody_argv(opts) do
    []
    |> put_flag("--path", opts[:busybody_path])
    |> put_flag("--name", opts[:name])
  end

  defp put_flag(argv, _flag, nil), do: argv
  defp put_flag(argv, flag, value), do: argv ++ [flag, to_string(value)]

  defp put_switch(argv, _flag, false), do: argv
  defp put_switch(argv, flag, true), do: argv ++ [flag]
end
