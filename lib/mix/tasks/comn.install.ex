if Code.ensure_loaded?(Igniter) do
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

    Requires [Igniter](https://hexdocs.pm/igniter) in the host project's deps
    (`{:igniter, "~> 0.8", only: [:dev, :test]}`). Without it, this task is an
    inert stub that prints an install hint.
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
      opts = igniter.args.options

      igniter
      |> Igniter.Project.Deps.add_dep(comn_dep(opts))
      |> maybe_context_plug(opts)
      |> maybe_error_registry(opts)
      |> Igniter.add_notice("""
      Comn installed.

        * Run `mix deps.get`.
        * Implement `@behaviour Comn` on discoverable infrastructure modules.
        * Set request context at boundaries (the generated Context plug does this).
        * Declare error codes with `register_error/3` in your Errors registry.
      """)
    end

    defp maybe_error_registry(igniter, opts) do
      if opts[:error_registry] == false do
        igniter
      else
        app = opts[:name] && String.to_atom(opts[:name])
        app = app || Igniter.Project.Application.app_name(igniter)
        registry_module = Module.concat([Macro.camelize(to_string(app)), "Errors"])

        Igniter.Project.Module.create_module(igniter, registry_module, registry_body())
      end
    end

    defp registry_body do
      """
      @moduledoc \"\"\"
      Compile-time error registry for this app. Declare codes with
      `register_error/3`; look them up via `Comn.Errors.Registry`.
      \"\"\"
      use Comn.Errors.Registry

      # register_error "app/invalid_input", :validation,
      #   message: "Input was invalid", status: 422
      """
    end

    defp maybe_context_plug(igniter, opts) do
      if opts[:context_plug] == false do
        igniter
      else
        web = Igniter.Libs.Phoenix.web_module(igniter)
        plug_module = Module.concat([web, "Plugs", "Context"])

        igniter
        |> Igniter.Project.Module.create_module(plug_module, plug_body())
        |> wire_pipelines(plug_module)
      end
    end

    defp wire_pipelines(igniter, plug_module) do
      {igniter, router} = Igniter.Libs.Phoenix.select_router(igniter)

      if router do
        line = "plug #{inspect(plug_module)}"

        igniter
        |> append_to_pipeline_once(:browser, line, plug_module, router)
        |> append_to_pipeline_once(:api, line, plug_module, router)
      else
        Igniter.add_warning(
          igniter,
          "No Phoenix router found; skipped wiring #{inspect(plug_module)}. Add it to your pipelines manually."
        )
      end
    end

    # Like Igniter.Libs.Phoenix.append_to_pipeline/4 but skips insertion when
    # the plug call is already present in the target pipeline.
    defp append_to_pipeline_once(igniter, pipeline_name, line, plug_module, router) do
      Igniter.Project.Module.find_and_update_module!(igniter, router, fn zipper ->
        case Igniter.Code.Function.move_to_function_call_in_current_scope(
               zipper,
               :pipeline,
               2,
               fn z -> Igniter.Code.Function.argument_equals?(z, 0, pipeline_name) end
             ) do
          {:ok, pipeline_zipper} ->
            case Igniter.Code.Common.move_to_do_block(pipeline_zipper) do
              {:ok, do_zipper} ->
                already_present =
                  match?(
                    {:ok, _},
                    Igniter.Code.Function.move_to_function_call_in_current_scope(
                      do_zipper,
                      :plug,
                      1,
                      fn z -> Igniter.Code.Function.argument_equals?(z, 0, plug_module) end
                    )
                  )

                if already_present do
                  {:ok, zipper}
                else
                  {:ok, Igniter.Code.Common.add_code(do_zipper, line)}
                end

              :error ->
                {:ok, zipper}
            end

          _ ->
            {:ok, zipper}
        end
      end)
    end

    defp plug_body do
      """
      @moduledoc \"\"\"
      Sets a process-scoped `Comn.Contexts` at the request boundary so
      downstream errors and events auto-enrich with the request id.
      \"\"\"
      @behaviour Plug

      @impl true
      def init(opts), do: opts

      @impl true
      def call(conn, _opts) do
        Comn.Contexts.new(request_id: request_id(conn))
        conn
      end

      defp request_id(conn) do
        case Plug.Conn.get_resp_header(conn, "x-request-id") do
          [id | _] -> id
          _ -> Logger.metadata()[:request_id]
        end
      end
      """
    end

    defp comn_dep(opts) do
      if opts[:git],
        do: {:comn, git: opts[:git]},
        else: {:comn, path: opts[:path] || "../comn"}
    end
  end
else
  defmodule Mix.Tasks.Comn.Install do
    @shortdoc "Install the Comn foundation into a Phoenix app"
    @moduledoc false

    use Mix.Task

    @impl Mix.Task
    def run(_argv) do
      Mix.shell().error("""
      The task 'comn.install' requires igniter. Please install igniter and try again.

      For more information, see: https://hexdocs.pm/igniter/readme.html#installation
      """)

      exit({:shutdown, 1})
    end
  end
end
