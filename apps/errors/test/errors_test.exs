defmodule Comn.ErrorsTest do
  use ExUnit.Case, async: true

  alias Comn.Errors
  alias Comn.Errors.ErrorStruct
  alias Comn.Error

  describe "ErrorStruct" do
    test "new/4 creates a struct with all fields" do
      err = ErrorStruct.new("validation", "email", "invalid format", "use user@domain.com")
      assert err.reason == "validation"
      assert err.field == "email"
      assert err.message == "invalid format"
      assert err.suggestion == "use user@domain.com"
    end

    test "new/3 creates a struct without suggestion" do
      err = ErrorStruct.new("internal", nil, "something broke")
      assert is_nil(err.suggestion)
    end

    test "to_string renders reason and message" do
      err = ErrorStruct.new("network", nil, "connection refused")
      assert to_string(err) == "[network] connection refused"
    end
  end

  describe "Comn.Error protocol" do
    test "converts a map with atom keys" do
      err = Error.to_error(%{reason: "auth", field: "token", message: "expired", suggestion: "refresh"})
      assert %ErrorStruct{} = err
      assert err.reason == "auth"
    end

    test "converts a map with string keys" do
      err = Error.to_error(%{"reason" => "auth", "field" => "token", "message" => "expired", "suggestion" => "refresh"})
      assert %ErrorStruct{} = err
      assert err.reason == "auth"
    end

    test "converts a 4-tuple" do
      err = Error.to_error({"persistence", "id", "not found", "check ID"})
      assert %ErrorStruct{} = err
      assert err.reason == "persistence"
    end

    test "passes through an existing ErrorStruct" do
      original = ErrorStruct.new("internal", nil, "oops")
      assert Error.to_error(original) == original
    end

    test "converts a string" do
      err = Error.to_error("something went wrong")
      assert %ErrorStruct{} = err
      assert err.message == "something went wrong"
      assert err.reason == "unknown"
    end

    test "converts an atom" do
      err = Error.to_error(:timeout)
      assert %ErrorStruct{} = err
      assert err.reason == "timeout"
    end
  end

  describe "Comn.Errors" do
    test "categories/0 returns known categories" do
      cats = Errors.categories()
      assert :validation in cats
      assert :persistence in cats
      assert :network in cats
      assert :auth in cats
      assert :internal in cats
      assert :unknown in cats
    end

    test "wrap/1 delegates to protocol" do
      err = Errors.wrap("test error")
      assert %ErrorStruct{} = err
    end

    test "new/2 creates a categorized error" do
      err = Errors.new(:validation, "bad input")
      assert %ErrorStruct{} = err
      assert err.reason == "validation"
      assert err.message == "bad input"
    end

    test "categorize/1 detects validation" do
      assert Errors.categorize("invalid email format") == :validation
    end

    test "categorize/1 detects persistence" do
      assert Errors.categorize("database connection timeout") == :persistence
    end

    test "categorize/1 detects network" do
      assert Errors.categorize("connection refused") == :network
    end

    test "categorize/1 detects auth" do
      assert Errors.categorize("unauthorized access denied") == :auth
    end

    test "categorize/1 falls back to internal" do
      assert Errors.categorize("something unexpected") == :internal
    end

    test "categorize/1 handles atoms" do
      assert Errors.categorize(:timeout) == :persistence
    end
  end
end
