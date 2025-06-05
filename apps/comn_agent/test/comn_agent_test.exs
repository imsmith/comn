defmodule ComnAgentTest do
  use ExUnit.Case
  doctest ComnAgent

  test "greets the world" do
    assert ComnAgent.hello() == :world
  end
end
