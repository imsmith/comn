defmodule Mix.Tasks.Comn.InstallTest do
  @moduledoc false
  use ExUnit.Case, async: true
  import Igniter.Test

  test "adds the comn path dep to mix.exs" do
    phx_test_project()
    |> Igniter.compose_task("comn.install", ["--no-context-plug", "--no-error-registry"])
    |> assert_has_patch("mix.exs", """
    + |      {:comn, [path: "../comn"]},
    """)
  end

  test "generates a starter error registry at lib/<app>/errors.ex" do
    igniter =
      phx_test_project()
      |> Igniter.compose_task("comn.install", ["--no-context-plug"])

    assert_creates(igniter, "lib/test/errors.ex", """
    defmodule Test.Errors do
      @moduledoc \"\"\"
      Compile-time error registry for this app. Declare codes with
      `register_error/3`; look them up via `Comn.Errors.Registry`.
      \"\"\"
      use Comn.Errors.Registry

      # register_error "app/invalid_input", :validation,
      #   message: "Input was invalid", status: 422
    end
    """)
  end

  test "--no-error-registry and --no-context-plug suppress their artifacts" do
    igniter =
      phx_test_project()
      |> Igniter.compose_task("comn.install", ["--no-context-plug", "--no-error-registry"])

    refute_creates(igniter, "lib/test/errors.ex")
    refute_creates(igniter, "lib/test_web/plugs/context.ex")
  end

  test "is idempotent — a second run produces no further changes" do
    {:ok, after_first, _} =
      phx_test_project()
      |> Igniter.compose_task("comn.install", [])
      |> apply_igniter()

    after_first
    |> Igniter.compose_task("comn.install", [])
    |> assert_unchanged()
  end

  test "generates the Contexts boundary plug and wires it into pipelines" do
    igniter =
      phx_test_project()
      |> Igniter.compose_task("comn.install", ["--no-error-registry"])

    assert_creates(igniter, "lib/test_web/plugs/context.ex", """
    defmodule TestWeb.Plugs.Context do
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
    """)

    assert_has_patch(igniter, "lib/test_web/router.ex", """
    + |    plug(TestWeb.Plugs.Context)
    """)
  end
end
