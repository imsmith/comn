defmodule Comn.Repo.File.Root do
  @moduledoc """
  Confines every file path a backend touches to a caller-declared root.

  A backend is opened with `root:` (NFS calls it `mount:`); the path it is
  asked for is resolved against that root and refused if it lands outside.
  A relative path is joined to the root; an absolute path must already be
  under it. `..` segments are normalised away before the check.
  """

  alias Comn.Errors.Registry, as: ErrReg

  # ponytail: symlinks inside the root are followed, so a link that points
  # outside escapes. Resolve real paths component by component if the root
  # can contain links the caller does not control.
  @doc "The absolute path for `path` under `root`, or `repo.file/outside_root`."
  @spec resolve(String.t(), String.t()) ::
          {:ok, String.t()} | {:error, Comn.Errors.ErrorStruct.t()}
  def resolve(root, path) when is_binary(root) and is_binary(path) do
    root = Path.expand(root)
    full = Path.expand(path, root)

    if full == root or String.starts_with?(full, root <> "/"),
      do: {:ok, full},
      else:
        {:error, ErrReg.error!("repo.file/outside_root", field: path, message: "escapes #{root}")}
  end

  @doc "`resolve/2` with the root taken from `opts[key]`; `repo.file/invalid_opts` when absent."
  @spec resolve(keyword(), atom(), String.t()) ::
          {:ok, String.t()} | {:error, Comn.Errors.ErrorStruct.t()}
  def resolve(opts, key, path) when is_list(opts) and is_atom(key) do
    case Keyword.fetch(opts, key) do
      {:ok, root} when is_binary(root) ->
        resolve(root, path)

      _ ->
        {:error,
         ErrReg.error!("repo.file/invalid_opts",
           field: to_string(key),
           suggestion: "pass #{key}: \"/abs/dir\" to confine paths"
         )}
    end
  end
end
