defmodule ComnAllTest do
  use ExUnit.Case
  doctest ComnAll

  test "greets the world" do
    assert ComnAll.hello() == :world
  end
end
