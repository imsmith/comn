if Code.ensure_loaded?(Credo.Check) do
  defmodule Comn.Credo.RawShell do
    @moduledoc """
    Flags direct process execution: `System.cmd`, `System.shell`, `:os.cmd`,
    and `Port.open` with a spawn tuple.

    `Comn.Repo.Cmd` is the execution boundary where blast radius is
    classified and authorized; a raw shell call bypasses it. Implementations
    of `Comn.Repo.Cmd` are the legitimate callers.

    Ships with comn; `credo` is an optional dependency. A consumer lists the
    check in `.credo.exs`:

        {Comn.Credo.RawShell, []}
    """
    use Credo.Check,
      base_priority: :high,
      category: :warning,
      explanations: [
        check: """
        Direct process execution bypasses `Comn.Repo.Cmd`, which is the
        execution boundary where blast radius is classified and authorized.

            System.cmd("git", args)      # flagged
            System.shell("ls | wc -l")   # flagged
            :os.cmd(~c"ls")              # flagged
            Port.open({:spawn, "ls"}, [])# flagged

        Implementations of `Comn.Repo.Cmd` are the legitimate callers; exclude
        them per-check in `.credo.exs` with `files: %{excluded: [...]}`.
        """
      ]

    @impl true
    def run(%SourceFile{} = source_file, params) do
      meta = IssueMeta.for(source_file, params)

      Comn.Credo.Check.prewalk(source_file, fn
        {{:., _, [{:__aliases__, _, [:System]}, f]}, _, _} = node, line, issues
        when f in [:cmd, :shell] ->
          [issue(meta, node, line) | issues]

        {{:., _, [:os, :cmd]}, _, _} = node, line, issues ->
          [issue(meta, node, line) | issues]

        {{:., _, [{:__aliases__, _, [:Port]}, :open]}, _, [{:{}, _, [kind | _]} | _]} = node,
        line,
        issues
        when kind in [:spawn, :spawn_executable] ->
          [issue(meta, node, line) | issues]

        {{:., _, [{:__aliases__, _, [:Port]}, :open]}, _, [{kind, _} | _]} = node, line, issues
        when kind in [:spawn, :spawn_executable] ->
          [issue(meta, node, line) | issues]

        _node, _line, issues ->
          issues
      end)
    end

    defp issue(meta, node, line) do
      format_issue(meta,
        message: "Raw process execution; go through a Comn.Repo.Cmd implementation.",
        trigger: Macro.to_string(node),
        line_no: line
      )
    end
  end
end
