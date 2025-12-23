defmodule Comn.Repo.Cmd.Shell do
  @moduledoc """
    A repo implementation for executing shell commands.
  """

  @behaviour Comn.Repo
  @behaviour Comn.Repo.Cmd

  @impl true
  def describe(term) do
    {:ok, %{type: :shell, description: "Shell command repository", term: term}}
  end

  @impl true
  def delete(term, keyword) do
    {:ok, %{type: :shell, action: :delete, term: term, keyword: keyword}} |> IO.inspect(label: "Delete Command")
    :ok
  end

  @impl true
  def get(term, keyword) do
    {:ok, %{type: :shell, action: :get, term: term, keyword: keyword}} |> IO.inspect(label: "Get Command")
    # Simulate command execution
    {:ok, "Simulated output for get command"}
  end

  @impl true
  def observe(term, keyword) do
    {:ok, %{type: :shell, action: :observe, term: term, keyword: keyword}} |> IO.inspect(label: "Observe Command")
    :ok # Placeholder, should return an Enumerable
  end

  @impl true
  def set(term, keyword) do
    {:ok, %{type: :shell, action: :set, term: term, keyword: keyword}} |> IO.inspect(label: "Set Command")
    :ok
  end

  @impl true
  def validate(term, opts \\ []) do
    # Checks the validity of a proposed config without applying it
  end

  @impl true
  def apply(term, opts \\ []) do
    # enacts a previously staged or defined configuration
  end

  @impl true
  def reset(term,opts \\ []) do
    # Resets the resource to default or factory settings
  end

  @impl true
  def enable(term, opts \\[]) do
    # enables a toggleable resource
  end

  @impl true
  def disable(term, opts \\ []) do
    # disables a toggleable resource
  end

  @impl true
  def sync(term, opts \\ []) do
    # forces reconciliation between the declared and observed state
  end

  @impl true
  def status(term, opts \\ []) do
    # provides a high-level summary of health/state
  end

  @impl true
  def test(term, opts \\ []) do
    # actively probes functionality
  end

  @impl true
  def invoke(term, opts \\ []) do
    # runs a non-declarative operation (like `restart`)
  end

  @impl true
  def info(term) do
    # alias to describe
    describe(term)
    {:ok, nil}
  end

  @impl true
  def watch(term, opts \\ []) do
    # alias to observe
    observe(term, opts)
    {:ok, nil}
  end

  @impl true
  def run(term, opts \\ []) do
    # alias to invoke
    invoke(term, opts)
    {:ok, nil}
  end

  @impl true
  def probe(term, opts \\ []) do
    # alias to test
    test(term, opts)
    {:ok, nil}
  end
end
