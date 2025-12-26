Feature: Backend Interoperability
  As a developer using Comn.Secrets
  I want to switch backends without changing my application code
  So that I can change infrastructure without refactoring

  Scenario: Same interface across Local and Vault backends
    Given I have the same plaintext "secret data"
    And I have equivalent keys for Local and Vault
    When I lock with Local backend
    And I lock with Vault backend
    Then both operations should return {:ok, %LockedBlob{}}
    And both should have the same struct fields
    And both should unlock to the same plaintext
    Because the interface is backend-agnostic

  Scenario: LockedBlob structure is consistent
    Given I lock data with Local backend
    And I lock data with Vault backend
    Then both LockedBlobs should have:
      | field      |
      | cipher     |
      | encrypted  |
      | tag        |
      | key_hint   |
      | nonce      |
      | metadata   |
    And no backend-specific fields should be required

  Scenario: Error types are standardized across backends
    Given Local backend fails with invalid key
    And Vault backend fails with invalid key
    Then both should return {:error, :invalid_key}
    Not backend-specific error codes

  Scenario: Key structure works for both backends
    Given a Comn.Secrets.Key struct
    When I add metadata %{vault_addr: "...", vault_token: "..."} for Vault
    Or I use it as-is for Local
    Then both backends should accept the same Key struct
    And backend-specific info goes in metadata only

  Scenario: Switching backends requires only configuration change
    Given my application code calls:
      """
      {:ok, locked} = @secrets_backend.lock(data, key)
      """
    When I change @secrets_backend from Local to Vault
    Then no application code changes are required
    And the function signature remains identical

  Scenario: Both backends pass identical security tests
    Given SecurityTestCase defines 20 security tests
    When I run tests against Local backend
    Then all 20 tests should pass
    When I run tests against Vault backend
    Then all 20 tests should pass
    And the same test code runs for both

  Scenario: Container operations work identically
    Given I wrap 3 secrets with Local backend
    And I wrap 3 secrets with Vault backend
    Then both should return {:ok, %LockedBlob{}}
    And unwrap should work the same way for both
    Because wrap/unwrap interface is standardized
