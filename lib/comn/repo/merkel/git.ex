defmodule Comn.Repo.Merkel.Git do
  @moduledoc false
  # Git-backed merkel: a bare repository at :path with one branch,
  # refs/heads/comn. Each put writes the content as a blob, wraps it in a
  # one-entry tree, and commits it on top of the current head; the address
  # is the commit id and the content address is the blob id. Git hashes
  # every object itself and refuses to read a corrupt one, so check/2 is
  # "git could read it". State is the repository path; nothing is held in
  # memory, so close is a no-op and several handles may share a path.
  #
  # ponytail: every verb shells out to git once or more. Fine for audit
  # chains; use a libgit2 NIF if throughput ever matters.

  @behaviour Comn.Repo.Merkel.Backend

  alias Comn.Errors.Registry, as: ErrReg
  alias Comn.Repo.Merkel.Node

  @ref "refs/heads/comn"
  @env [
    {"GIT_AUTHOR_NAME", "comn"},
    {"GIT_AUTHOR_EMAIL", "comn@localhost"},
    {"GIT_COMMITTER_NAME", "comn"},
    {"GIT_COMMITTER_EMAIL", "comn@localhost"}
  ]

  @impl true
  def open(_name, opts) do
    with {:ok, path} <- path_opt(opts), :ok <- ensure_bare(path), do: {:ok, path}
  end

  defp path_opt(opts) do
    case Keyword.fetch(opts, :path) do
      {:ok, path} when is_binary(path) ->
        {:ok, path}

      _ ->
        {:error,
         ErrReg.error!("repo.merkel/invalid_opts",
           field: "path",
           suggestion: "pass path: \"/abs/repo.git\""
         )}
    end
  end

  defp ensure_bare(path) do
    if File.dir?(Path.join(path, "objects")) do
      :ok
    else
      File.mkdir_p!(path)

      case git(path, ["init", "--bare", "-q"]) do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, backend_error(reason)}
      end
    end
  end

  @impl true
  def close(_path), do: :ok

  @impl true
  def drop(path) do
    File.rm_rf!(path)
    :ok
  end

  @impl true
  def put(path, content) when is_binary(content) do
    tmp = Path.join(path, "comn-put-#{System.unique_integer([:positive])}")
    File.write!(tmp, content)

    try do
      with :ok <- ensure_repo(path),
           {:ok, blob} <- git(path, ["hash-object", "-w", tmp]),
           {:ok, tree} <-
             sh(path, "printf '100644 blob %s\\tcontent\\n' \"$1\" | git mktree", [blob]),
           {:ok, parent} <- head(path),
           {:ok, commit} <-
             git(path, ["commit-tree", tree, "-m", "comn put"] ++ parent_args(parent)),
           {:ok, _} <- git(path, ["update-ref", @ref, commit]) do
        {:ok, commit}
      else
        {:error, %Comn.Errors.ErrorStruct{} = err} -> {:error, err}
        {:error, reason} -> {:error, backend_error(reason)}
      end
    after
      File.rm(tmp)
    end
  end

  @impl true
  def node(path, address) do
    with :ok <- ensure_repo(path),
         {:ok, "commit"} <- git(path, ["cat-file", "-t", address]),
         {:ok, commit} <- git(path, ["cat-file", "-p", address]),
         {:ok, tree_id} <- field(commit, "tree"),
         {:ok, tree} <- git(path, ["cat-file", "-p", tree_id]),
         [_mode, "blob", blob_id] <- tree |> String.split("\t") |> hd() |> String.split(" "),
         {:ok, content} <- git(path, ["cat-file", "blob", blob_id], raw: true) do
      parent =
        case field(commit, "parent") do
          {:ok, p} -> p
          :error -> nil
        end

      {:ok,
       %Node{
         address: address,
         parent: parent,
         content_address: blob_id,
         content: content,
         algo: :git
       }}
    else
      {:error, %Comn.Errors.ErrorStruct{} = err} -> {:error, err}
      _ -> {:error, ErrReg.error!("repo.merkel/unknown_address", field: address)}
    end
  end

  @impl true
  def head(path) do
    with :ok <- ensure_repo(path) do
      case git(path, ["rev-parse", "--verify", "-q", @ref]) do
        {:ok, sha} -> {:ok, sha}
        {:error, _} -> {:ok, nil}
      end
    end
  end

  @impl true
  def length(path) do
    with :ok <- ensure_repo(path), {:ok, head} <- head(path), do: count_commits(path, head)
  end

  defp count_commits(_path, nil), do: {:ok, 0}

  defp count_commits(path, _head) do
    with {:ok, n} <- git(path, ["rev-list", "--count", @ref]), do: {:ok, String.to_integer(n)}
  end

  # git verifies an object's hash whenever it reads it; node/2 already read
  # the commit, tree and blob. Re-read the blob to be explicit.
  @impl true
  def check(path, %Node{content_address: blob_id, content: content}) do
    case git(path, ["cat-file", "blob", blob_id], raw: true) do
      {:ok, ^content} -> :ok
      _ -> :tampered
    end
  end

  @doc false
  # Where git keeps a loose object; tests corrupt it to prove verify/1 notices.
  def object_path(path, <<prefix::binary-size(2), rest::binary>>),
    do: Path.join([path, "objects", prefix, rest])

  # ---- internals ----

  defp parent_args(nil), do: []
  defp parent_args(parent), do: ["-p", parent]

  defp field(commit, key) do
    commit
    |> String.split("\n")
    |> Enum.find_value(:error, fn line ->
      case String.split(line, " ", parts: 2) do
        [^key, value] -> {:ok, value}
        _ -> nil
      end
    end)
  end

  defp ensure_repo(path) do
    if File.dir?(Path.join(path, "objects")),
      do: :ok,
      else: {:error, ErrReg.error!("repo.merkel/not_found", field: path)}
  end

  defp git(path, args, opts \\ []) do
    case System.cmd("git", ["--git-dir", path | args], env: @env, stderr_to_stdout: true) do
      {out, 0} -> {:ok, if(opts[:raw], do: out, else: String.trim(out))}
      {out, code} -> {:error, {code, String.trim(out)}}
    end
  end

  # for the one command that needs stdin
  defp sh(path, script, args) do
    case System.cmd("sh", ["-c", script, "sh" | args],
           env: [{"GIT_DIR", path} | @env],
           stderr_to_stdout: true
         ) do
      {out, 0} -> {:ok, String.trim(out)}
      {out, code} -> {:error, {code, String.trim(out)}}
    end
  end

  defp backend_error(reason),
    do: ErrReg.error!("repo.merkel/backend_error", message: "git: #{inspect(reason)}")
end
