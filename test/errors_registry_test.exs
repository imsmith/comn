defmodule Comn.Test.SampleErrors do
  @moduledoc false
  use Comn.Errors.Registry

  register_error "auth/invalid_token",   :auth,       message: "Token is invalid or expired", status: 401
  register_error "auth/forbidden",       :auth,       message: "Insufficient permissions", status: 403
  register_error "repo/not_found",       :persistence, message: "Resource not found", status: 404
  register_error "input/bad_format",     :validation,  message: "Invalid input format", status: 422, suggestion: "Check the API docs"
end

defmodule Comn.Test.ConflictingErrors do
  @moduledoc false
  use Comn.Errors.Registry

  register_error "auth/invalid_token", :auth, message: "Duplicate code from another module"
end

defmodule Comn.Errors.RegistryTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias Comn.Errors.Registry
  alias Comn.Errors.ErrorStruct

  setup do
    # Ensure Comn's codes and sample codes are all registered.
    # Don't reset — other async tests depend on the registry.
    Registry.discover()
    Registry.register_module(Comn.Test.SampleErrors)
    :ok
  end

  describe "register_module/1" do
    test "indexes a module's errors" do
      assert length(Registry.all()) >= 4
      assert Enum.any?(Registry.all(), &(&1.code == "auth/invalid_token"))
    end

    test "rejects modules without __errors__/0" do
      assert {:error, :not_a_registry_module} = Registry.register_module(String)
    end

    test "rejects duplicate codes from different modules" do
      assert {:error, {:duplicate_code, "auth/invalid_token", Comn.Test.SampleErrors}} =
               Registry.register_module(Comn.Test.ConflictingErrors)
    end

    test "allows re-registering the same module (idempotent)" do
      count_before = length(Registry.all())
      assert :ok = Registry.register_module(Comn.Test.SampleErrors)
      assert length(Registry.all()) == count_before
    end
  end

  describe "code format validation" do
    test "valid codes compile" do
      # These are already compiled in Comn.Test.SampleErrors above:
      # "auth/invalid_token", "auth/forbidden", "repo/not_found", "input/bad_format"
      assert length(Comn.Test.SampleErrors.__errors__()) == 4
    end

    test "invalid codes raise CompileError" do
      assert_raise CompileError, ~r/invalid error code/, fn ->
        Code.compile_string("""
        defmodule Comn.Test.BadCode1 do
          use Comn.Errors.Registry
          register_error "InvalidCode", :auth, message: "bad"
        end
        """)
      end

      assert_raise CompileError, ~r/invalid error code/, fn ->
        Code.compile_string("""
        defmodule Comn.Test.BadCode2 do
          use Comn.Errors.Registry
          register_error "auth/token/expired", :auth, message: "two slashes"
        end
        """)
      end

      assert_raise CompileError, ~r/invalid error code/, fn ->
        Code.compile_string("""
        defmodule Comn.Test.BadCode3 do
          use Comn.Errors.Registry
          register_error "auth/invalid-token", :auth, message: "hyphens"
        end
        """)
      end

      assert_raise CompileError, ~r/invalid error code/, fn ->
        Code.compile_string("""
        defmodule Comn.Test.BadCode4 do
          use Comn.Errors.Registry
          register_error "Auth/Token", :auth, message: "uppercase"
        end
        """)
      end

      assert_raise CompileError, ~r/invalid error code/, fn ->
        Code.compile_string("""
        defmodule Comn.Test.BadCode5 do
          use Comn.Errors.Registry
          register_error "nonamespace", :auth, message: "no slash"
        end
        """)
      end
    end

    test "dot-separated namespaces are valid" do
      [{mod, _binary}] = Code.compile_string("""
      defmodule Comn.Test.DottedNS do
        use Comn.Errors.Registry
        register_error "repo.table/not_found", :persistence, message: "table miss"
        register_error "repo.file.ipfs/cid_invalid", :validation, message: "bad CID"
      end
      """)

      errors = mod.__errors__()
      codes = Enum.map(errors, & &1.code) |> Enum.sort()
      assert codes == ["repo.file.ipfs/cid_invalid", "repo.table/not_found"]
    end
  end

  describe "lookup/1" do
    test "returns error definition by code" do
      defn = Registry.lookup("auth/invalid_token")
      assert defn.code == "auth/invalid_token"
      assert defn.category == :auth
      assert defn.message == "Token is invalid or expired"
      assert defn.status == 401
      assert defn.module == Comn.Test.SampleErrors
    end

    test "returns nil for unknown codes" do
      assert is_nil(Registry.lookup("nope/doesnt_exist"))
    end
  end

  describe "codes/0" do
    test "includes sample codes in sorted list" do
      codes = Registry.codes()
      assert "auth/forbidden" in codes
      assert "auth/invalid_token" in codes
      assert "input/bad_format" in codes
      assert "repo/not_found" in codes
      assert codes == Enum.sort(codes)
    end
  end

  describe "codes_for/1" do
    test "filters by category" do
      auth_codes = Registry.codes_for(:auth)
      assert "auth/forbidden" in auth_codes
      assert "auth/invalid_token" in auth_codes

      validation_codes = Registry.codes_for(:validation)
      assert "input/bad_format" in validation_codes
    end
  end

  describe "codes_for_prefix/1" do
    test "matches by code prefix" do
      assert "auth/forbidden" in Registry.codes_for_prefix("auth/")
      assert "auth/invalid_token" in Registry.codes_for_prefix("auth/")
      assert "input/bad_format" in Registry.codes_for_prefix("input/bad")
    end

    test "returns empty list for no matches" do
      assert Registry.codes_for_prefix("nope") == []
    end
  end

  describe "error/2" do
    test "creates an ErrorStruct from a registered code" do
      {:ok, err} = Registry.error("auth/invalid_token")
      assert %ErrorStruct{} = err
      assert err.code == "auth/invalid_token"
      assert err.reason == "auth"
      assert err.message == "Token is invalid or expired"
    end

    test "allows field and message overrides" do
      {:ok, err} = Registry.error("auth/invalid_token",
        field: "authorization",
        message: "Bearer token rejected"
      )

      assert err.field == "authorization"
      assert err.message == "Bearer token rejected"
      assert err.code == "auth/invalid_token"
    end

    test "populates suggestion from definition" do
      {:ok, err} = Registry.error("input/bad_format")
      assert err.suggestion == "Check the API docs"
    end

    test "enriches with ambient context" do
      Comn.Contexts.new(request_id: "req-999", trace_id: "trace-888")

      {:ok, err} = Registry.error("repo/not_found")
      assert err.request_id == "req-999"
      assert err.trace_id == "trace-888"
    end

    test "returns error for unknown code" do
      assert {:error, :unknown_code} = Registry.error("nope/missing")
    end
  end

  describe "http_status/1" do
    test "returns status for registered code" do
      assert Registry.http_status("auth/invalid_token") == 401
      assert Registry.http_status("auth/forbidden") == 403
      assert Registry.http_status("repo/not_found") == 404
    end

    test "returns nil for unknown code" do
      assert is_nil(Registry.http_status("nope/missing"))
    end
  end

  describe "discover/0" do
    test "finds modules with __errors__/0" do
      # discover is already called in setup; verify it found Comn's codes
      codes = Registry.codes()
      assert "secrets/invalid_key" in codes
      assert "repo.table/not_found" in codes
      assert "events.nats/connection_failed" in codes
    end
  end

  describe "__errors__/0 on declaring module" do
    test "generated function returns the error list" do
      errors = Comn.Test.SampleErrors.__errors__()
      assert is_list(errors)
      assert length(errors) == 4
      codes = Enum.map(errors, & &1.code) |> Enum.sort()
      assert codes == ["auth/forbidden", "auth/invalid_token", "input/bad_format", "repo/not_found"]
    end
  end
end
