defmodule Comn.Secrets.ExampleImplementationTest do
  @moduledoc """
  Example test file showing how to use the SecurityTestCase for your implementation.

  When you implement Comn.Secrets (e.g., Comn.Secrets.Local), create a test file
  that uses the SecurityTestCase to automatically verify all security requirements.

  ## Usage

      defmodule MyApp.Secrets.LocalTest do
        use ExUnit.Case
        use Comn.Secrets.SecurityTestCase, implementation: MyApp.Secrets.Local

        # All security tests are automatically included above

        # Add implementation-specific tests here
        describe "implementation-specific behavior" do
          test "custom test for Local backend" do
            # ...
          end
        end
      end

  ## Running Tests

      # Run all secret tests
      mix test apps/secrets/test

      # Run only security tests
      mix test apps/secrets/test/comn/secrets/security_test_case.ex

      # Run specific feature
      mix test --only key_validation

  ## Gherkin Features

  The tests implement the behavior specified in Gherkin feature files:

  - test/features/key_validation.feature
  - test/features/leakage_prevention.feature  
  - test/features/authentication.feature
  - test/features/nonce_uniqueness.feature
  - test/features/container_integrity.feature

  These features define the REQUIRED security behavior for any Comn.Secrets implementation.
  """

  # This is a placeholder - real implementations would uncomment and replace with their module
  # use ExUnit.Case
  # use Comn.Secrets.SecurityTestCase, implementation: Comn.Secrets.Local

  # When you have a real implementation:
  #
  # 1. Create a new test file: test/comn/secrets/local_test.exs
  # 2. Add:
  #      defmodule Comn.Secrets.LocalTest do
  #        use ExUnit.Case
  #        use Comn.Secrets.SecurityTestCase, implementation: Comn.Secrets.Local
  #      end
  # 3. Run: mix test
  # 4. All security requirements will be automatically verified
end
