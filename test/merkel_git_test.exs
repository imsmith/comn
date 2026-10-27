defmodule Comn.MerkelGitTest do
  @moduledoc """
  Phase 2: :git backend. Each put is a commit on a branch in a local bare
  repository; the address is the commit sha; verify walks the chain and
  lets git check every object's hash on read.

  Needs the git binary on PATH.
  """

  use ExUnit.Case, async: true

  # Must precede the conformance `use` lines.
  @moduletag :tmp_dir

  use Comn.MerkelConformance
  use Comn.EventSinkConformance, backend: Comn.Repo.Merkel

  alias Comn.Repo.Merkel
  alias Comn.Repo.Merkel.Git

  defp fresh_name, do: :"merkel_git_#{:erlang.unique_integer([:positive])}"

  def open_merkel(%{tmp_dir: dir}) do
    name = fresh_name()
    {:ok, m} = Merkel.open(name, backend: :git, path: Path.join(dir, "#{name}.git"))
    {m, fn -> Merkel.drop(m) end}
  end

  def open_sink(ctx), do: open_merkel(ctx)

  # Corrupt the loose object file for the commit's blob so git refuses to read it.
  def tamper(%Merkel.Handle{} = m, address) do
    {:ok, %Merkel.Node{} = node} = Merkel.node(m, address)
    path = Git.object_path(m.state, node.content_address)
    File.chmod!(path, 0o644)
    File.write!(path, "garbage")
    :ok
  end

  describe ":git lifecycle" do
    @tag :merkel_phase2
    test "open/2 requires a :path" do
      assert {:error, %Comn.Errors.ErrorStruct{code: "repo.merkel/invalid_opts"}} =
               Merkel.open(fresh_name(), backend: :git)
    end

    @tag :merkel_phase2
    test "open/2 initialises a bare repository and reopens it with its chain", %{tmp_dir: dir} do
      name = fresh_name()
      path = Path.join(dir, "reopen.git")
      {:ok, m} = Merkel.open(name, backend: :git, path: path)
      assert File.dir?(Path.join(path, "objects"))
      {:ok, a} = Merkel.put(m, entry(%{n: 1}))
      :ok = Merkel.close(m)

      {:ok, m} = Merkel.open(name, backend: :git, path: path)
      assert {:ok, ^a} = Merkel.head(m)
      assert {:ok, %{data: %{n: 1}}} = Merkel.get(m, a)
      assert :ok = Merkel.verify(m)
      Merkel.drop(m)
    end

    @tag :merkel_phase2
    test "addresses are commit shas git itself resolves", %{tmp_dir: dir} do
      path = Path.join(dir, "sha.git")
      {:ok, m} = Merkel.open(fresh_name(), backend: :git, path: path)
      {:ok, a} = Merkel.put(m, entry())
      # git is the oracle here; routing it through Comn.Repo.Cmd would verify Comn with Comn.
      # credo:disable-for-next-line Comn.Credo.RawShell
      {out, 0} = System.cmd("git", ["--git-dir", path, "cat-file", "-t", a])
      assert String.trim(out) == "commit"
      Merkel.drop(m)
    end

    @tag :merkel_phase2
    test "drop/1 deletes the repository", %{tmp_dir: dir} do
      path = Path.join(dir, "gone.git")
      {:ok, m} = Merkel.open(fresh_name(), backend: :git, path: path)
      assert :ok = Merkel.drop(m)
      refute File.exists?(path)
      assert :ok = Merkel.drop(m)
    end
  end
end
