defmodule ComnSecretsTest do
  use ExUnit.Case
  doctest ComnSecrets

  test "greets the world" do
    assert ComnSecrets.hello() == :world
  end
end
