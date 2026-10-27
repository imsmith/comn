if Code.ensure_loaded?(Credo.Check) do
  defmodule Comn.Credo.Check do
    @moduledoc """
    Shared traversal for Comn doctrine checks.

    `prewalk/2` walks an AST like `Credo.Code.prewalk/2` but skips pattern
    positions (case/fn clause heads, `=` and `<-` left sides, def heads), so
    matching on an external library's `{:error, :enoent}` is not flagged.
    Literal 2-tuples carry no metadata, so the nearest enclosing line is
    passed alongside each node.
    """

    @doc "Walk expression positions only; `fun` receives `(node, line, issues)` and returns issues."
    def prewalk(source_file, fun) do
      ast = Credo.SourceFile.ast(source_file)
      {_, {_, issues}} = Macro.prewalk(ast, {0, []}, &step(&1, &2, fun))
      issues
    end

    defp step(node, {line, issues}, fun) do
      line =
        with {_, m, _} when is_list(m) <- node,
             l when is_integer(l) <- m[:line],
             do: l,
             else: (_ -> line)

      {strip(node), {line, fun.(node, line, issues)}}
    end

    # Drop pattern sub-trees so prewalk never descends into them.
    defp strip({:->, m, [_heads, body]}), do: {:->, m, [[], body]}
    defp strip({op, m, [_lhs, rhs]}) when op in [:=, :<-], do: {op, m, [nil, rhs]}
    defp strip({d, m, [_head, body]}) when d in [:def, :defp], do: {d, m, [nil, body]}
    defp strip(node), do: node
  end
end
