defmodule Comn.Events.RegistryTest do
  use ExUnit.Case, async: true

  test "Comn.Events.Registry module is loaded" do
    assert Code.ensure_loaded?(Comn.Events.Registry)
  end

  test "Comn.Events.Registry defines subscribe" do
    assert {:subscribe, 1} in Comn.Events.Registry.__info__(:functions)
  end

  test "Comn.Events.Registry defines broadcast" do
    assert {:broadcast, 2} in Comn.Events.Registry.__info__(:functions)
  end
end
