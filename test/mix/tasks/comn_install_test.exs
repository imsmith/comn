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
end
