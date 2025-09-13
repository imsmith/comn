defmodule ErrorsTest do
  use ExUnit.Case, async: true
  doctest Errors

  test "greets the world" do
    assert Errors.hello() == :world
  end
end
