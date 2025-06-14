defmodule ErrorsTest do
  use ExUnit.Case
  doctest Errors

  test "greets the world" do
    assert Errors.hello() == :world
  end
end
