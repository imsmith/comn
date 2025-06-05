defmodule ComnInfraTest do
  use ExUnit.Case
  doctest ComnInfra

  test "greets the world" do
    assert ComnInfra.hello() == :world
  end
end
