defmodule Mix.Tasks.Comn.Install do
  @shortdoc "Generate the Comn boundary plug and error registry for a Phoenix app"
  @moduledoc """
  Generates the two files a host Phoenix app needs to use Comn, then prints
  the edits it will not make for you.

      mix comn.install

  Creates `lib/<app>_web/plugs/context.ex` (a `Comn.Contexts` boundary plug)
  and `lib/<app>/errors.ex` (a starter error registry). Existing files are
  never overwritten. Adding the `:comn` dep to `mix.exs` and the plug to your
  router pipelines are two lines you edit by hand; the task prints both.

  ## Options

    * `--name` - OTP app name for generated modules (default: this project's)
    * `--no-context-plug` - skip the Contexts boundary plug
    * `--no-error-registry` - skip the starter error registry
  """

  use Mix.Task

  @switches [name: :string, context_plug: :boolean, error_registry: :boolean]

  @impl Mix.Task
  def run(argv) do
    {opts, _, _} = OptionParser.parse(argv, switches: @switches)
    app = opts[:name] || to_string(Mix.Project.config()[:app])
    base = Macro.camelize(app)

    unless opts[:context_plug] == false do
      create("lib/#{app}_web/plugs/context.ex", plug_source("#{base}Web.Plugs.Context"))
    end

    unless opts[:error_registry] == false do
      create("lib/#{app}/errors.ex", registry_source("#{base}.Errors"))
    end

    Mix.shell().info("""

    Two edits left to make by hand:

      * mix.exs deps:      {:comn, path: "../comn"}
      * router pipelines:  plug #{base}Web.Plugs.Context

    Then `mix deps.get`, implement `@behaviour Comn` on infrastructure modules,
    and declare error codes with `register_error/3` in #{base}.Errors.
    """)
  end

  defp create(path, contents) do
    if File.exists?(path),
      do: Mix.shell().info("* skipping #{path} (exists)"),
      else: Mix.Generator.create_file(path, contents)
  end

  @doc false
  def plug_source(module) do
    """
    defmodule #{module} do
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
    end
    """
  end

  @doc false
  def registry_source(module) do
    """
    defmodule #{module} do
      @moduledoc \"\"\"
      Compile-time error registry for this app. Declare codes with
      `register_error/3`; look them up via `Comn.Errors.Registry`.
      \"\"\"
      use Comn.Errors.Registry

      # register_error "app/invalid_input", :validation,
      #   message: "Input was invalid", status: 422
    end
    """
  end
end
