Feature: HashiCorp Vault Backend Integration
  As a developer using Comn.Secrets
  I want to use HashiCorp Vault as a backend
  So that I can leverage Vault's security features while keeping my application interface constant

  Background:
    Given a running HashiCorp Vault instance
    And Vault is unsealed and accessible
    And the Transit secrets engine is enabled at "transit/"

  Scenario: Lock and unlock with Vault Transit engine
    Given I have a Vault authentication token
    And I create a Vault transit key named "test-key"
    And I create a Comn.Secrets.Key referencing "test-key"
    When I lock "secret data" with the Vault key
    Then I should receive a LockedBlob
    And the LockedBlob should contain Vault-format ciphertext
    When I unlock the LockedBlob with the same key
    Then I should receive "secret data"

  Scenario: Vault backend passes all security tests
    Given I have a Vault transit key
    When I run the SecurityTestCase tests against Comn.Secrets.Vault
    Then all key validation tests should pass
    And all nonce uniqueness tests should pass
    And all authentication tests should pass
    And all container integrity tests should pass
    Because the interface must remain constant across backends

  Scenario: Vault manages encryption keys, not the application
    Given a Vault transit key named "app-key"
    And I have a Comn.Secrets.Key with vault_key_name "app-key"
    When I lock data
    Then the application should never see the actual encryption key
    And Vault should perform the encryption operation
    And the key material should never leave Vault

  Scenario: Vault ciphertext format is preserved
    Given I lock "test data" with Vault backend
    When I inspect the LockedBlob.encrypted field
    Then it should contain Vault's base64-encoded ciphertext
    And it should start with "vault:v" prefix
    And the nonce should be embedded in the Vault ciphertext
    Because Vault Transit uses its own format

  Scenario: Vault connection failures are handled gracefully
    Given Vault is unreachable
    When I attempt to lock "secret data"
    Then I should receive error {:error, :vault_unavailable}
    And no plaintext should be leaked in the error

  Scenario: Vault authentication token in key metadata
    Given I have a Vault token "s.1234567890"
    When I create a Key with metadata %{vault_token: "s.1234567890", vault_addr: "http://localhost:8200"}
    And I lock data with this key
    Then the Vault client should use the provided token
    And the token should not appear in the LockedBlob

  Scenario: Vault key rotation is transparent to the application
    Given I lock "secret v1" with Vault key at version 1
    And Vault rotates the key to version 2
    When I lock "secret v2" with the same key reference
    Then both LockedBlobs should unlock successfully
    And Vault should handle key versioning internally
    Because the application interface doesn't change

  Scenario: Container wrap/unwrap with Vault
    Given I lock three secrets with Vault backend
    When I wrap them in a container
    Then the container serialization should be encrypted by Vault
    And unwrap should decrypt via Vault
    And the interface should be identical to Local backend

  Scenario: Vault-specific errors map to standard errors
    Given Vault returns "permission denied" error
    When unlock fails
    Then I should receive {:error, :authentication_failed}
    Not a Vault-specific error code
    Because error interface must be consistent across backends

  Scenario: Concurrent lock operations use Vault safely
    Given 100 concurrent lock operations
    When all operations complete
    Then all LockedBlobs should have unique nonces
    And all should unlock successfully
    And Vault should handle concurrent requests correctly
