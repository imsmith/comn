defmodule Comn.Repo.File.LocalTest do
  use ExUnit.Case, async: true

  alias Comn.Repo.File.{Local, FileStruct}
  alias Comn.Errors.ErrorStruct

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

      assert {:ok, %FileStruct{state: :open} = fs} = Local.open(path)
      assert {:ok, %FileStruct{state: :loaded, buffer: "test content"} = fs} = Local.load(fs)
      assert {:ok, "test content"} = Local.read(fs)
      assert :ok = Local.close(fs)
    end
  end

  describe "lifecycle: open → load → write → close" do
    test "writes data through lifecycle" do
      path = tmp_file("")

      assert {:ok, fs} = Local.open(path, mode: [:write, :binary])
      assert {:ok, fs} = Local.load(fs)
      assert {:ok, fs} = Local.write(fs, "written data")
      assert :ok = Local.close(fs)

      assert File.read!(path) == "written data"
    end
  end

  describe "lifecycle: open → load → stream → cast" do
    test "streams and casts file content" do
      path = tmp_file("line1\nline2\nline3\n")

      assert {:ok, fs} = Local.open(path)
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
      {:ok, fs} = Local.open(path)
      assert {:error, %ErrorStruct{code: "repo.file/invalid_state"}} = Local.read(fs)
      Local.close(fs)
    end

    test "load without open fails" do
      fs = %FileStruct{state: :init, backend: Local}
      assert {:error, %ErrorStruct{code: "repo.file/invalid_state"}} = Local.load(fs)
    end

    test "write without load fails" do
      path = tmp_file()
      {:ok, fs} = Local.open(path)
      assert {:error, %ErrorStruct{code: "repo.file/invalid_state"}} = Local.write(fs, "data")
      Local.close(fs)
    end

    test "stream without load fails" do
      path = tmp_file()
      {:ok, fs} = Local.open(path)
      assert {:error, %ErrorStruct{code: "repo.file/invalid_state"}} = Local.stream(fs)
      Local.close(fs)
    end

    test "cast without load fails" do
      path = tmp_file()
      {:ok, fs} = Local.open(path)
      assert {:error, %ErrorStruct{code: "repo.file/invalid_state"}} = Local.cast(fs)
      Local.close(fs)
    end
  end

  describe "error cases" do
    test "open nonexistent file returns error" do
      assert {:error, :enoent} = Local.open("/tmp/comn_nonexistent_#{System.unique_integer()}")
    end
  end

  describe "Comn.Repo callbacks" do
    test "describe returns file metadata" do
      path = tmp_file("some data")
      {:ok, fs} = Local.open(path)
      assert {:ok, info} = Local.describe(fs)
      assert info.path == path
      assert info.state == :open
      assert info.size > 0
      Local.close(fs)
    end

    test "get returns buffer when loaded" do
      path = tmp_file("get test")
      {:ok, fs} = Local.open(path)
      {:ok, fs} = Local.load(fs)
      assert {:ok, "get test"} = Local.get(fs, [])
      Local.close(fs)
    end

    test "get fails when not loaded" do
      path = tmp_file()
      {:ok, fs} = Local.open(path)
      assert {:error, %ErrorStruct{code: "repo.file/invalid_state"}} = Local.get(fs, [])
      Local.close(fs)
    end

    test "delete removes the file" do
      path = tmp_file("delete me")
      {:ok, fs} = Local.open(path)
      Local.close(fs)
      assert :ok = Local.delete(fs, [])
      refute File.exists?(path)
    end
  end
end

defmodule Comn.Repo.File.NFSTest do
  use ExUnit.Case, async: true

  alias Comn.Repo.File.{NFS, FileStruct}

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

    {:ok, fs} = NFS.open(file, mount: mount)
    {:ok, fs} = NFS.load(fs)
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

  alias Comn.Repo.File.{IPFS, FileStruct}
  alias Comn.Errors.ErrorStruct

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
