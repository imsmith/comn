defmodule Mix.Tasks.Comn.InstallTest do
  alias Mix.Tasks.Comn.Install

  @moduledoc false
  use ExUnit.Case, async: false

  @tmp Path.join(System.tmp_dir!(), "comn_install_test")

  setup do
    File.rm_rf!(@tmp)
    File.mkdir_p!(@tmp)
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    :ok
  end

  test "generates plug and registry, skips existing files, prints the manual edits" do
    File.cd!(@tmp, fn ->
      Install.run(["--name", "demo"])

      assert File.read!("lib/demo_web/plugs/context.ex") =~ "defmodule DemoWeb.Plugs.Context"
      assert File.read!("lib/demo/errors.ex") =~ "use Comn.Errors.Registry"
      assert_received {:mix_shell, :info, ["\nTwo edits" <> _ = msg]}
      assert msg =~ "plug DemoWeb.Plugs.Context"

      File.write!("lib/demo/errors.ex", "keep")
      Install.run(["--name", "demo"])
      assert File.read!("lib/demo/errors.ex") == "keep"
    end)
  end

  test "--no-context-plug and --no-error-registry suppress their files" do
    File.cd!(@tmp, fn ->
      Install.run(["--name", "demo", "--no-context-plug", "--no-error-registry"])
      refute File.exists?("lib/demo_web/plugs/context.ex")
      refute File.exists?("lib/demo/errors.ex")
    end)
  end
end
