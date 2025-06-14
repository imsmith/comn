defmodule RepoTest do
  use ExUnit.Case
  doctest Repo

  test "greets the world" do
    assert Repo.hello() == :world
  end
end
