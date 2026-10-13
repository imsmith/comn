if Code.ensure_loaded?(Ecto.Repo) do
  defmodule Comn.Repo.Table.Ecto.Repos do
    @moduledoc false
    # Turns repository configuration into a running Ecto repo.
    #
    #   repo: MyApp.Repo            an existing, already-started repo module
    #   ecto: [adapter: A, ...]     build a repo module for adapter A at runtime
    #   ecto: "path/to/repo.exs"    a file whose last expression is that keyword
    #
    # Ecto fixes the adapter when the repo module is compiled, so "any
    # adapter" means compiling a module per configuration. They are cached
    # by a hash of the config and started once under
    # Comn.Repo.Table.Ecto.Supervisor; the same config gives the same repo.

    alias Comn.Errors.Registry, as: ErrReg

    @supervisor Comn.Repo.Table.Ecto.Supervisor

    @spec ensure(keyword()) :: {:ok, module()} | {:error, Comn.Errors.ErrorStruct.t()}
    def ensure(opts) do
      cond do
        is_atom(opts[:repo]) and not is_nil(opts[:repo]) ->
          {:ok, opts[:repo]}

        not is_nil(opts[:ecto]) ->
          with {:ok, cfg} <- load(opts[:ecto]),
               {:ok, adapter, rest} <- split_adapter(cfg),
               {:ok, mod} <- define(adapter, cfg),
               :ok <- start(mod, rest) do
            {:ok, mod}
          end

        true ->
          {:error,
           ErrReg.error!("repo.table/invalid_opts",
             field: "ecto",
             suggestion: "pass ecto: [adapter: ..., ...], ecto: \"repo.exs\", or repo: MyApp.Repo"
           )}
      end
    end

    defp load(path) when is_binary(path) do
      case Code.eval_file(path) do
        {cfg, _} when is_list(cfg) or is_map(cfg) ->
          load(cfg)

        _ ->
          {:error,
           ErrReg.error!("repo.table/invalid_opts",
             field: "ecto",
             message: "#{path} must return a keyword or map"
           )}
      end
    rescue
      e ->
        {:error,
         ErrReg.error!("repo.table/invalid_opts", field: "ecto", message: Exception.message(e))}
    end

    defp load(cfg) when is_map(cfg), do: {:ok, Map.to_list(cfg)}
    defp load(cfg) when is_list(cfg), do: {:ok, cfg}
    defp load(_), do: {:error, ErrReg.error!("repo.table/invalid_opts", field: "ecto")}

    defp split_adapter(cfg) do
      case Keyword.fetch(cfg, :adapter) do
        {:ok, adapter} when is_atom(adapter) ->
          if Code.ensure_loaded?(adapter),
            do: {:ok, adapter, Keyword.delete(cfg, :adapter)},
            else:
              {:error,
               ErrReg.error!("repo.table/invalid_opts",
                 field: "adapter",
                 message: "#{inspect(adapter)} is not on the code path"
               )}

        _ ->
          {:error,
           ErrReg.error!("repo.table/invalid_opts",
             field: "adapter",
             suggestion: "e.g. Ecto.Adapters.SQLite3"
           )}
      end
    end

    defp define(adapter, cfg) do
      hash =
        :crypto.hash(:sha256, :erlang.term_to_binary(Enum.sort(cfg), [:deterministic]))
        |> Base.encode16()
        |> binary_part(0, 16)

      mod = Module.concat(Comn.Repo.Table.Ecto.Dyn, "R" <> hash)

      unless Code.ensure_loaded?(mod) do
        Module.create(
          mod,
          quote(do: use(Ecto.Repo, otp_app: :comn, adapter: unquote(adapter))),
          Macro.Env.location(__ENV__)
        )
      end

      {:ok, mod}
    rescue
      e ->
        {:error,
         ErrReg.error!("repo.table/invalid_opts", field: "adapter", message: Exception.message(e))}
    end

    defp start(mod, cfg) do
      case DynamicSupervisor.start_child(@supervisor, {mod, cfg}) do
        {:ok, _} ->
          :ok

        {:error, {:already_started, _}} ->
          :ok

        {:error, reason} ->
          {:error,
           ErrReg.error!("repo.table/invalid_opts",
             field: "ecto",
             message: "repo failed to start: #{inspect(reason)}"
           )}
      end
    end
  end
end
