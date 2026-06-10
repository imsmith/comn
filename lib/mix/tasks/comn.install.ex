defmodule Mix.Tasks.Comn.Install do
  @shortdoc "Install the Comn foundation into a Phoenix app"
  @moduledoc """
  Wires Comn into a host Phoenix application.

      mix comn.install

  Adds the `:comn` dependency. Unless suppressed, also generates a
  `Comn.Contexts` boundary plug (wired into the router) and a starter
  error registry module.

  ## Options

    * `--path` - path dep source (default `../comn`)
    * `--git` - use a git dep instead of a path dep
    * `--name` - app name for generated artifacts (default: OTP app)
    * `--no-context-plug` - skip the Contexts boundary plug
    * `--no-error-registry` - skip the starter error registry
  """

  use Igniter.Mix.Task

  @impl Igniter.Mix.Task
  def info(_argv, _composing_task) do
    %Igniter.Mix.Task.Info{
      group: :comn,
      example: "mix comn.install --name my_app",
      schema: [
        path: :string,
        git: :string,
        name: :string,
        context_plug: :boolean,
        error_registry: :boolean
      ],
      defaults: [context_plug: true, error_registry: true]
    }
  end

  @impl Igniter.Mix.Task
  def igniter(igniter) do
    Igniter.Project.Deps.add_dep(igniter, comn_dep(igniter.args.options))
  end

  defp comn_dep(opts) do
    cond do
      opts[:git] -> {:comn, git: opts[:git]}
      true -> {:comn, path: opts[:path] || "../comn"}
    end
  end
end
