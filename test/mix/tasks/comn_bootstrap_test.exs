defmodule Mix.Tasks.Comn.BootstrapTest do
  @moduledoc false
  use ExUnit.Case, async: true
  import Igniter.Test

  test "adds both deps and composes comn.install" do
    igniter =
      phx_test_project()
      |> Igniter.compose_task("comn.bootstrap", ["--no-context-plug", "--no-error-registry"])

    assert_has_patch(igniter, "mix.exs", """
    + |      {:comn, [path: "../comn"]},
    """)

    assert_has_patch(igniter, "mix.exs", """
    + |      {:busybody, [path: "../busybody", only: :dev]},
    """)
  end

  test "--no-busybody adds only the comn dep" do
    igniter =
      phx_test_project()
      |> Igniter.compose_task("comn.bootstrap", [
        "--no-busybody",
        "--no-context-plug",
        "--no-error-registry"
      ])

    assert_has_patch(igniter, "mix.exs", """
    + |      {:comn, [path: "../comn"]},
    """)

    {:ok, applied, _} = apply_igniter(igniter)
    mix_exs = applied.rewrite |> Rewrite.source!("mix.exs") |> Rewrite.Source.get(:content)
    refute mix_exs =~ ":busybody"
  end
end
