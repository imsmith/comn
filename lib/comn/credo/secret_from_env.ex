if Code.ensure_loaded?(Credo.Check) do
  defmodule Comn.Credo.SecretFromEnv do
    @moduledoc """
    Flags secret-looking names read straight from the environment or app config.

    `System.get_env("VAULT_TOKEN")` and `Application.get_env(:app, :api_key)`
    put plaintext secrets where every process, log line, and crash dump can
    see them. `Comn.Secrets` is the boundary they belong behind. The name
    pattern is a parameter (`pattern:`), defaulting to secret, token,
    password, api_key, private_key, and credential, case-insensitive.

    Ships with comn; `credo` is an optional dependency. A consumer lists the
    check in `.credo.exs`:

        {Comn.Credo.SecretFromEnv, []}
    """
    use Credo.Check,
      base_priority: :high,
      category: :warning,
      param_defaults: [pattern: ~r/secret|token|passw|api_key|private_key|credential/i],
      explanations: [
        check: """
        A secret-looking name read straight from the environment or app config
        bypasses `Comn.Secrets`. Plaintext secrets in env/config are visible to
        every process, log line, and crash dump on the host.

            System.get_env("VAULT_TOKEN")                 # flagged
            Application.get_env(:app, :api_key)           # flagged
            Comn.Secrets.unlock(blob, key)                # use this
        """,
        params: [pattern: "Regex matched against the env var or config key name."]
      ]

    @env_fns [:get_env, :fetch_env, :fetch_env!]
    @cfg_fns [:get_env, :fetch_env, :fetch_env!, :compile_env, :compile_env!]

    @impl true
    def run(%SourceFile{} = source_file, params) do
      meta = IssueMeta.for(source_file, params)
      pattern = Params.get(params, :pattern, __MODULE__)

      Comn.Credo.Check.prewalk(source_file, fn
        {{:., _, [{:__aliases__, _, [:System]}, f]}, _, [name | _]} = node, line, issues
        when f in @env_fns ->
          flag(node, name, line, issues, pattern, meta, "Comn.Secrets")

        {{:., _, [{:__aliases__, _, [:Application]}, f]}, _, [_app, key | _]} = node, line, issues
        when f in @cfg_fns ->
          flag(node, key, line, issues, pattern, meta, "Comn.Secrets")

        _node, _line, issues ->
          issues
      end)
    end

    defp flag(node, name, line, issues, pattern, meta, want)
         when is_binary(name) or is_atom(name) do
      if Regex.match?(pattern, to_string(name)) do
        [
          format_issue(meta,
            message:
              "Secret-looking #{inspect(name)} read from env/config; route it through #{want}.",
            trigger: Macro.to_string(node),
            line_no: line
          )
          | issues
        ]
      else
        issues
      end
    end

    defp flag(_node, _dynamic, _line, issues, _pattern, _meta, _want), do: issues
  end
end
