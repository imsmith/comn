defmodule ComnRepoCmdTest do
  use ExUnit.Case
  doctest ComnRepoCmd

  test "greets the world" do
    assert ComnRepoCmd.hello() == :world
  end
end
