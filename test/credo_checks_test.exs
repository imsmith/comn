defmodule Comn.CredoChecksTest do
  use Credo.Test.Case

  setup_all do
    {:ok, _} = Application.ensure_all_started(:credo)
    :ok
  end

  alias Comn.Credo.{BareErrorAtom, RawShell, SecretFromEnv}

  describe "BareErrorAtom" do
    test "flags bare atom returns, not pattern matches" do
      """
      defmodule M do
        def a({:error, :from_head}), do: {:error, :bad}
        def b(x) do
          case File.read(x) do
            {:error, :enoent} -> {:error, :missing}
            {:ok, _} -> :ok
          end
        end
        def c, do: with {:error, :estale} <- f(), do: {:error, %Comn.Errors.ErrorStruct{}}
        def d, do: {:error, :nope} = g()
      end
      """
      |> to_source_file()
      |> run_check(BareErrorAtom)
      |> assert_issues(fn issues ->
        assert Enum.map(issues, & &1.trigger) |> Enum.sort() == [
                 "{:error, :bad}",
                 "{:error, :missing}"
               ]

        assert Enum.map(issues, & &1.line_no) |> Enum.sort() == [2, 5]
      end)
    end
  end

  describe "SecretFromEnv" do
    test "flags secret-looking names only" do
      """
      defmodule M do
        def a, do: System.get_env("VAULT_TOKEN")
        def b, do: Application.get_env(:app, :api_key)
        def c, do: System.fetch_env!("PORT")
        def d(n), do: System.get_env(n)
      end
      """
      |> to_source_file()
      |> run_check(SecretFromEnv)
      |> assert_issues(fn issues ->
        assert Enum.map(issues, & &1.line_no) |> Enum.sort() == [2, 3]
      end)
    end
  end

  describe "RawShell" do
    test "flags every raw execution form" do
      """
      defmodule M do
        def a, do: System.cmd("git", [])
        def b, do: System.shell("ls")
        def c, do: :os.cmd(~c"ls")
        def d, do: Port.open({:spawn, "ls"}, [])
        def e, do: File.read("x")
      end
      """
      |> to_source_file()
      |> run_check(RawShell)
      |> assert_issues(fn issues ->
        assert Enum.map(issues, & &1.line_no) |> Enum.sort() == [2, 3, 4, 5]
      end)
    end
  end
end
