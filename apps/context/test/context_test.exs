defmodule ContextTest do
  use ExUnit.Case
  doctest Context

  test "greets the world" do
    assert Context.hello() == :world
  end
end
