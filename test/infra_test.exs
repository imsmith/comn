defmodule Comn.InfraTest do
  use ExUnit.Case, async: true

  test "Comn.Infra module exists" do
    assert Code.ensure_loaded?(Comn.Infra)
  end
end
