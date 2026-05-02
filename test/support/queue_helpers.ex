defmodule Comn.Repo.QueueHelpers do
  @moduledoc """
  Test helpers for `Comn.Repo.Queue` tests across backends.

  Both backends share an identical contract; tests that run against
  both are easier to author when they don't have to remember which
  backend they're using.
  """

  @doc """
  Opens a queue against the given backend, registers an `on_exit`
  cleanup, and returns the handle. Use `tmp_dir` from ExUnit
  `@moduletag :tmp_dir` for SQLite paths.
  """
  def open_queue!(backend, opts \\ []) do
    name = Keyword.get_lazy(opts, :name, fn -> "q_#{System.unique_integer([:positive])}" end)
    discipline = Keyword.get(opts, :discipline, :fifo)

    open_opts =
      case backend do
        :mem ->
          [backend: :mem, discipline: discipline]

        :sqlite ->
          path = Keyword.fetch!(opts, :path)
          [backend: :sqlite, discipline: discipline, path: path]
      end

    {:ok, q} = Comn.Repo.Queue.open(name, open_opts)
    ExUnit.Callbacks.on_exit(fn -> Comn.Repo.Queue.close(q) end)
    q
  end
end
