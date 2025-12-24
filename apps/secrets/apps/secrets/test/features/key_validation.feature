Feature: Key Validation
  As a security-conscious developer
  I want the secrets implementation to reject malformed keys
  So that weak or invalid keys cannot be used for encryption

  Background:
    Given a Comn.Secrets implementation

  Scenario: Reject Ed25519 key with wrong private key size
    Given an Ed25519 key with 16-byte private key
    And a 32-byte public key
    When I attempt to lock "secret data" with the malformed key
    Then I should receive an error
    And the error should be :invalid_key

  Scenario: Reject Ed25519 key with wrong public key size
    Given an Ed25519 key with 32-byte private key
    And a 16-byte public key
    When I attempt to lock "secret data" with the malformed key
    Then I should receive an error
    And the error should be :invalid_key

  Scenario: Reject key with missing private key
    Given an Ed25519 key with nil private key
    And a 32-byte public key
    When I attempt to lock "secret data" with the incomplete key
    Then I should receive an error
    And the error should be :invalid_key

  Scenario: Reject key with algorithm/size mismatch
    Given a key claiming to be RSA-4096
    But with Ed25519-sized key material
    When I attempt to lock "secret data" with the mismatched key
    Then I should receive an error
    And the error should be :invalid_key

  Scenario: Accept valid Ed25519 key
    Given a valid Ed25519 key with 32-byte keys
    When I attempt to lock "secret data" with the valid key
    Then I should receive a success result
    And the result should contain a LockedBlob
