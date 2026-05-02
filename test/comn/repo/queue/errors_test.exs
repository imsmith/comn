defmodule Comn.Repo.Queue.ErrorsTest do
  @moduledoc """
  Unit tests for `Comn.Repo.Queue.Errors` registration.
  """

  use ExUnit.Case, async: true

  alias Comn.Errors.Registry

  setup do
    Code.ensure_loaded!(Comn.Repo.Queue.Errors)
    Registry.discover()
    :ok
  end

  test "queue error codes are registered with expected categories" do
    assert %{category: :persistence} = Registry.lookup("repo.queue/open_failed")
    assert %{category: :persistence} = Registry.lookup("repo.queue/corrupt")
    assert %{category: :validation} = Registry.lookup("repo.queue/item_not_found")
    assert %{category: :validation} = Registry.lookup("repo.queue/invalid_opts")
    assert %{category: :persistence} = Registry.lookup("repo.queue/reserve_failed")
  end

  test "all queue codes share the repo.queue prefix" do
    assert ["repo.queue/" <> _ | _] = Registry.codes_for_prefix("repo.queue/")
  end
end
