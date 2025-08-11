defmodule ContextsTest do
  use ExUnit.Case
  doctest Contexts

  test "greets the world" do
    assert Contexts.hello() == :world
  end
end
