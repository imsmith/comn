defmodule ComnRepoActorTest do
  use ExUnit.Case
  doctest ComnRepoActor

  test "greets the world" do
    assert ComnRepoActor.hello() == :world
  end
end
