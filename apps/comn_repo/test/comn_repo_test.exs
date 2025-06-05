defmodule ComnRepoTest do
  use ExUnit.Case
  doctest ComnRepo

  test "greets the world" do
    assert ComnRepo.hello() == :world
  end
end
