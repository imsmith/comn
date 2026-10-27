# One module per backend; each supplies open_sink/1 and runs the shared
# Comn.EventSinkConformance spec (ADR-0001). Stream backends run it from
# their own test files, where the lifecycle helpers already live.

defmodule Comn.EventSink.TableTest do
  use ExUnit.Case, async: true
  use Comn.EventSinkConformance, backend: Comn.Repo.Table.ETS

  alias Comn.Repo.Table.ETS

  def open_sink(_ctx) do
    name = :"sink_table_#{System.unique_integer([:positive])}"
    {:ok, _} = ETS.create(name)
    {name, fn -> ETS.drop(name) end}
  end
end

defmodule Comn.EventSink.ColumnTest do
  use ExUnit.Case, async: true
  use Comn.EventSinkConformance, backend: Comn.Repo.Column.ETS

  alias Comn.Repo.Column.ETS

  def open_sink(_ctx) do
    name = :"sink_column_#{System.unique_integer([:positive])}"
    {:ok, store} = ETS.create(name)
    {store, fn -> ETS.drop(store) end}
  end
end

defmodule Comn.EventSink.GraphTest do
  use ExUnit.Case, async: true
  use Comn.EventSinkConformance, backend: Comn.Repo.Graphs.Graph

  alias Comn.Repo.Graphs.Graph

  def open_sink(_ctx) do
    {:ok, g} = Graph.create(name: "sink")
    {g, fn -> :ok end}
  end
end

defmodule Comn.EventSink.FileTest do
  use ExUnit.Case, async: true
  @moduletag :tmp_dir
  use Comn.EventSinkConformance, backend: Comn.Repo.File.Local

  alias Comn.Repo.File.Local

  def open_sink(%{tmp_dir: dir}) do
    path = Path.join(dir, "sink.log")
    {:ok, fs} = Local.open(path, mode: [:read, :append, :binary])
    {:ok, fs} = Local.load(fs)
    {fs, fn -> File.rm(path) end}
  end
end

defmodule Comn.EventSink.BatchTest do
  use ExUnit.Case, async: true
  use Comn.EventSinkConformance, backend: Comn.Repo.Batch.Mem

  alias Comn.Repo.Batch.Mem

  def open_sink(_ctx) do
    name = :"sink_batch_#{System.unique_integer([:positive])}"

    {:ok, pid} =
      Mem.start_link(
        name: name,
        max_size: 1_000,
        interval_ms: 0,
        on_flush: fn _ -> :ok end
      )

    {name, fn -> if Process.alive?(pid), do: GenServer.stop(pid) end}
  end
end

defmodule Comn.EventSink.QueueMemTest do
  use ExUnit.Case, async: true
  use Comn.EventSinkConformance, backend: Comn.Repo.Queue

  alias Comn.Repo.Queue

  def open_sink(_ctx) do
    {:ok, q} = Queue.open("sink_q_#{System.unique_integer([:positive])}", backend: :mem)
    {q, fn -> Queue.close(q) end}
  end
end

defmodule Comn.EventSink.QueueSQLiteTest do
  use ExUnit.Case, async: true
  @moduletag :tmp_dir
  use Comn.EventSinkConformance, backend: Comn.Repo.Queue

  alias Comn.Repo.Queue

  def open_sink(%{tmp_dir: dir}) do
    name = "sink_q_#{System.unique_integer([:positive])}"
    {:ok, q} = Queue.open(name, backend: :sqlite, path: Path.join(dir, name <> ".db"))
    {q, fn -> Queue.close(q) end}
  end
end
