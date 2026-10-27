if Code.ensure_loaded?(Credo.Check) do
  defmodule Comn.Credo.BareErrorAtom do
    @moduledoc false
    use Credo.Check,
      base_priority: :high,
      category: :design,
      explanations: [
        check: """
        Comn's error convention: every error is a `Comn.Errors.ErrorStruct`
        with a registered code, never a bare atom.

            {:error, :not_found}                              # flagged
            {:error, ErrReg.error!("repo.table/not_found", field: id)}

        Pattern matches on external libraries' bare atoms are not flagged.
        """
      ]

    @impl true
    def run(%SourceFile{} = source_file, params) do
      meta = IssueMeta.for(source_file, params)

      Comn.Credo.Check.prewalk(source_file, fn
        {:error, atom} = node, line, issues when is_atom(atom) ->
          [
            format_issue(meta,
              message:
                "Bare error atom #{inspect(atom)}; return a Comn.Errors.ErrorStruct via Comn.Errors.Registry.error!/2.",
              trigger: Macro.to_string(node),
              line_no: line
            )
            | issues
          ]

        _node, _line, issues ->
          issues
      end)
    end
  end
end
