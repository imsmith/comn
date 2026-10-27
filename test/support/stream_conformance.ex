defmodule Comn.StreamConformance do
  @moduledoc """
  Shared acceptance spec for `Comn.Repo.Stream` backends, run entirely
  through the public facade so it proves backend fungibility.

  A backend test module does:

      use Comn.StreamConformance

      def open_stream(_ctx) do
        name = :"stream_\#{System.unique_integer([:positive])}"
        {:ok, s} = Comn.Repo.Stream.open(name, backend: :mem)
        {s, fn -> Comn.Repo.Stream.drop(s) end}
      end

  `open_stream/1` receives the ExUnit context and returns a handle plus a
  cleanup function. Any `@moduletag` the backend needs (`:tmp_dir`, `:nats`)
  must be declared **before** the `use` line, since the tests are defined
  at that point. Lifecycle details are the backend module's own tests.

  The spec is two macros this module composes: `Comn.StreamConformance.Log`
  (append/read/head/tail, `:stream_phase1`) and `Comn.StreamConformance.Sink`
  (the `Comn.Repo` verbs, `:stream_phase1`, and live subscribe,
  `:stream_phase2a`). Both rely on the `event/2` and `open!/1` helpers
  defined here, so use them through this module.
  """

  defmacro __using__(_opts) do
    quote location: :keep do
      alias Comn.Events.EventStruct
      alias Comn.Repo.Stream

      defp event(payload \\ %{}, topic \\ "test.event") do
        EventStruct.new(:test, topic, payload)
      end

      defp open!(ctx) do
        {s, cleanup} = open_stream(ctx)
        on_exit(cleanup)
        s
      end

      use Comn.StreamConformance.Log
      use Comn.StreamConformance.Sink
    end
  end
end
