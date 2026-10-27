defmodule Comn.Repo.FileTest do
  @moduledoc """
  Acceptance spec for Comn.Repo.File (the facade) over its :local and :nfs
  backends. :ipfs needs a daemon and is covered by Comn.Repo.File.IPFSTest.
  """

  use ExUnit.Case, async: true
  @moduletag :tmp_dir
  use Comn.EventSinkConformance, backend: Comn.Repo.File

  doctest Comn.Repo.File

  alias Comn.Repo.File, as: F
  alias Comn.Repo.Handle

  defp tmp_file(dir, content \\ "hello world") do
    path = Path.join(dir, "f_#{:erlang.unique_integer([:positive])}.txt")
    File.write!(path, content)
    path
  end

  def open_sink(%{tmp_dir: dir}) do
    {:ok, f0} = F.open(tmp_file(dir, ""), root: dir, mode: [:read, :append, :binary])
    {:ok, f} = F.load(f0)
    {f, fn -> F.drop(f) end}
  end

  describe "facade" do
    @tag :file_phase1
    test "look/recon/choices/act behave as a Comn facade" do
      assert is_binary(F.look())
      assert %{type: :facade, extends: Comn.Repo, backends: backends} = F.recon()
      assert :local in backends and :nfs in backends and :ipfs in backends
      assert is_map(F.choices())

      assert {:error, %Comn.Errors.ErrorStruct{code: "comn/unknown_action"}} =
               F.act(%{action: :bogus})
    end

    @tag :file_phase1
    test "open/2 with an unknown backend is invalid_opts", %{tmp_dir: dir} do
      assert {:error, %Comn.Errors.ErrorStruct{code: "repo.file/invalid_opts"}} =
               F.open(tmp_file(dir), root: dir, backend: :abacus)
    end

    @tag :file_phase1
    test "open/2 on a missing file surfaces the OS reason", %{tmp_dir: dir} do
      assert {:error, :enoent} = F.open(Path.join(dir, "nope.txt"), root: dir)
    end

    @tag :file_phase1
    test "Comn.Repo.File.Local keeps its public surface", %{tmp_dir: dir} do
      {:ok, fs0} = F.Local.open(tmp_file(dir, "x"), root: dir)
      {:ok, fs} = F.Local.load(fs0)
      assert {:ok, "x"} = F.Local.read(fs)
      :ok = F.Local.close(fs)
    end
  end

  describe ":local lifecycle" do
    @tag :file_phase1
    test "open → load → read → close", %{tmp_dir: dir} do
      {:ok, f0} = F.open(tmp_file(dir, "content"), root: dir)
      assert %Handle{shape: F, backend: F.Adapter} = f0
      {:ok, f} = F.load(f0)
      assert {:ok, "content"} = F.read(f)
      assert {:ok, %{state: :loaded, size: 7}} = F.describe(f)
      assert :ok = F.close(f)
      assert :ok = F.close(f)
    end

    @tag :file_phase1
    test "open → load → write → close", %{tmp_dir: dir} do
      path = tmp_file(dir, "")
      {:ok, f0} = F.open(path, root: dir, mode: [:write, :binary])
      {:ok, f1} = F.load(f0)
      {:ok, f2} = F.write(f1, "written")
      :ok = F.close(f2)
      assert File.read!(path) == "written"
    end

    @tag :file_phase1
    test "stream yields lines; read before load is invalid_state", %{tmp_dir: dir} do
      {:ok, f0} = F.open(tmp_file(dir, "a\nb\n"), root: dir)

      assert {:error, %Comn.Errors.ErrorStruct{code: "repo.file/invalid_state"}} = F.read(f0)

      {:ok, f} = F.load(f0)
      assert {:ok, stream} = F.stream(f)
      assert Enum.to_list(stream) == ["a\n", "b\n"]
      F.close(f)
    end

    @tag :file_phase1
    test "drop/1 closes and deletes the file", %{tmp_dir: dir} do
      path = tmp_file(dir)
      {:ok, f} = F.open(path, root: dir)
      assert :ok = F.drop(f)
      refute File.exists?(path)
      assert :ok = F.drop(f)
    end
  end

  describe "paths are confined to root" do
    @tag :file_phase1
    test "open/2 without a root is invalid_opts", %{tmp_dir: dir} do
      assert {:error, %Comn.Errors.ErrorStruct{code: "repo.file/invalid_opts", field: "root"}} =
               F.open(tmp_file(dir))
    end

    @tag :file_phase1
    test "a relative path is joined to the root", %{tmp_dir: dir} do
      File.write!(Path.join(dir, "rel.txt"), "rel")
      {:ok, f0} = F.open("rel.txt", root: dir)
      {:ok, f} = F.load(f0)
      assert {:ok, "rel"} = F.read(f)
      F.close(f)
    end

    @tag :file_phase1
    test "a relative path that climbs out is outside_root", %{tmp_dir: dir} do
      assert {:error, %Comn.Errors.ErrorStruct{code: "repo.file/outside_root"}} =
               F.open("../../etc/passwd", root: dir)
    end

    @tag :file_phase1
    test "an absolute path outside the root is outside_root", %{tmp_dir: dir} do
      assert {:error, %Comn.Errors.ErrorStruct{code: "repo.file/outside_root"}} =
               F.open("/etc/passwd", root: dir)
    end

    @tag :file_phase1
    test "a sibling directory with the root as a prefix is outside_root", %{tmp_dir: dir} do
      assert {:error, %Comn.Errors.ErrorStruct{code: "repo.file/outside_root"}} =
               F.open(dir <> "_evil/x.txt", root: dir)
    end
  end

  describe ":nfs backend" do
    @tag :file_phase1
    test "resolves the path under the mount", %{tmp_dir: mount} do
      File.write!(Path.join(mount, "data.txt"), "nfs")
      {:ok, f0} = F.open("data.txt", backend: :nfs, mount: mount)
      {:ok, f} = F.load(f0)
      assert {:ok, "nfs"} = F.read(f)
      F.close(f)
    end

    @tag :file_phase1
    test "a path escaping the mount is refused", %{tmp_dir: mount} do
      assert {:error, %Comn.Errors.ErrorStruct{code: "repo.file/outside_root"}} =
               F.open("../escape.txt", backend: :nfs, mount: mount)
    end
  end
end

defmodule Comn.Repo.File.LocalTest do
  use ExUnit.Case, async: true

  alias Comn.Errors.ErrorStruct
  alias Comn.Repo.File.{FileStruct, Local}

  @tmp_dir System.tmp_dir!()

  defp tmp_file(content \\ "hello world") do
    path = Path.join(@tmp_dir, "comn_test_#{:erlang.unique_integer([:positive])}.txt")
    File.write!(path, content)
    on_exit(fn -> File.rm(path) end)
    path
  end

  describe "lifecycle: open → load → read → close" do
    test "reads file content through full lifecycle" do
      path = tmp_file("test content")

      assert {:ok, %FileStruct{state: :open} = fs} = Local.open(path, root: @tmp_dir)
      assert {:ok, %FileStruct{state: :loaded, buffer: "test content"} = fs} = Local.load(fs)
      assert {:ok, "test content"} = Local.read(fs)
      assert :ok = Local.close(fs)
    end
  end

  describe "lifecycle: open → load → write → close" do
    test "writes data through lifecycle" do
      path = tmp_file("")

      assert {:ok, fs} = Local.open(path, root: @tmp_dir, mode: [:write, :binary])
      assert {:ok, fs} = Local.load(fs)
      assert {:ok, fs} = Local.write(fs, "written data")
      assert :ok = Local.close(fs)

      assert File.read!(path) == "written data"
    end
  end

  describe "lifecycle: open → load → stream → cast" do
    test "streams and casts file content" do
      path = tmp_file("line1\nline2\nline3\n")

      assert {:ok, fs} = Local.open(path, root: @tmp_dir)
      assert {:ok, fs} = Local.load(fs)
      assert {:ok, stream} = Local.stream(fs)
      assert is_function(stream) or is_struct(stream, File.Stream)

      lines = Enum.to_list(stream)
      assert length(lines) == 3

      assert :ok = Local.cast(fs)
      assert :ok = Local.close(fs)
    end
  end

  describe "state enforcement" do
    test "read without load fails" do
      path = tmp_file()
      {:ok, fs} = Local.open(path, root: @tmp_dir)
      assert {:error, %ErrorStruct{code: "repo.file/invalid_state"}} = Local.read(fs)
      Local.close(fs)
    end

    test "load without open fails" do
      fs = %FileStruct{state: :init, backend: Local}
      assert {:error, %ErrorStruct{code: "repo.file/invalid_state"}} = Local.load(fs)
    end

    test "write without load fails" do
      path = tmp_file()
      {:ok, fs} = Local.open(path, root: @tmp_dir)
      assert {:error, %ErrorStruct{code: "repo.file/invalid_state"}} = Local.write(fs, "data")
      Local.close(fs)
    end

    test "stream without load fails" do
      path = tmp_file()
      {:ok, fs} = Local.open(path, root: @tmp_dir)
      assert {:error, %ErrorStruct{code: "repo.file/invalid_state"}} = Local.stream(fs)
      Local.close(fs)
    end

    test "cast without load fails" do
      path = tmp_file()
      {:ok, fs} = Local.open(path, root: @tmp_dir)
      assert {:error, %ErrorStruct{code: "repo.file/invalid_state"}} = Local.cast(fs)
      Local.close(fs)
    end
  end

  describe "error cases" do
    test "open nonexistent file returns error" do
      assert {:error, :enoent} =
               Local.open("/tmp/comn_nonexistent_#{System.unique_integer()}", root: @tmp_dir)
    end
  end

  describe "Comn.Repo callbacks" do
    test "describe returns file metadata" do
      path = tmp_file("some data")
      {:ok, fs} = Local.open(path, root: @tmp_dir)
      assert {:ok, info} = Local.describe(fs)
      assert info.path == path
      assert info.state == :open
      assert info.size > 0
      Local.close(fs)
    end

    test "get returns buffer when loaded" do
      path = tmp_file("get test")
      {:ok, fs0} = Local.open(path, root: @tmp_dir)
      {:ok, fs} = Local.load(fs0)
      assert {:ok, "get test"} = Local.get(fs, [])
      Local.close(fs)
    end

    test "get fails when not loaded" do
      path = tmp_file()
      {:ok, fs} = Local.open(path, root: @tmp_dir)
      assert {:error, %ErrorStruct{code: "repo.file/invalid_state"}} = Local.get(fs, [])
      Local.close(fs)
    end

    test "delete removes the file" do
      path = tmp_file("delete me")
      {:ok, fs} = Local.open(path, root: @tmp_dir)
      Local.close(fs)
      assert :ok = Local.delete(fs, [])
      refute File.exists?(path)
    end
  end
end

defmodule Comn.Repo.File.NFSTest do
  use ExUnit.Case, async: true

  alias Comn.Repo.File.{FileStruct, NFS}

  @tmp_dir System.tmp_dir!()

  defp setup_mount do
    mount = Path.join(@tmp_dir, "comn_nfs_mount_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(mount)
    on_exit(fn -> File.rm_rf!(mount) end)
    mount
  end

  test "open resolves path relative to mount point" do
    mount = setup_mount()
    file = "test.txt"
    File.write!(Path.join(mount, file), "nfs content")

    assert {:ok, %FileStruct{backend: Comn.Repo.File.NFS} = fs} =
             NFS.open(file, mount: mount)

    assert fs.path == Path.join(mount, file)
    assert fs.metadata.mount == mount
    NFS.close(fs)
  end

  test "full lifecycle through NFS" do
    mount = setup_mount()
    file = "lifecycle.txt"
    File.write!(Path.join(mount, file), "nfs data")

    {:ok, fs0} = NFS.open(file, mount: mount)
    {:ok, fs} = NFS.load(fs0)
    assert {:ok, "nfs data"} = NFS.read(fs)
    assert :ok = NFS.close(fs)
  end

  test "open nonexistent file returns error" do
    mount = setup_mount()
    assert {:error, :enoent} = NFS.open("missing.txt", mount: mount)
  end
end

defmodule Comn.Repo.File.IPFSTest do
  use ExUnit.Case, async: true

  alias Comn.Errors.ErrorStruct
  alias Comn.Repo.File.{FileStruct, IPFS}

  @moduletag :ipfs

  describe "state enforcement" do
    test "read without load fails" do
      fs = %FileStruct{state: :open, backend: IPFS, metadata: %{api: "http://localhost:5001"}}
      assert {:error, %ErrorStruct{code: "repo.file/invalid_state"}} = IPFS.read(fs)
    end

    test "load without open fails" do
      fs = %FileStruct{state: :init, backend: IPFS, metadata: %{api: "http://localhost:5001"}}
      assert {:error, %ErrorStruct{code: "repo.file/invalid_state"}} = IPFS.load(fs)
    end

    test "close on closed handle fails" do
      fs = %FileStruct{state: :closed, backend: IPFS, metadata: %{api: "http://localhost:5001"}}
      assert {:error, %ErrorStruct{code: "repo.file/invalid_state"}} = IPFS.close(fs)
    end
  end
end

defmodule Comn.Repo.File.BehaviourTest do
  use ExUnit.Case, async: true

  test "Comn.Repo.File behaviour defines lifecycle callbacks" do
    callbacks = Comn.Repo.File.behaviour_info(:callbacks)
    assert {:open, 2} in callbacks
    assert {:load, 2} in callbacks
    assert {:stream, 2} in callbacks
    assert {:cast, 2} in callbacks
    assert {:read, 2} in callbacks
    assert {:write, 3} in callbacks
    assert {:close, 2} in callbacks
  end
end
