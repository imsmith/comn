Feature: Leakage Prevention
  As a security-conscious developer
  I want error messages to never contain secrets or keys
  So that sensitive data is not exposed in logs or exceptions

  Background:
    Given a Comn.Secrets implementation
    And a valid Ed25519 key

  Scenario: Error messages do not contain plaintext
    Given I lock the plaintext "super_secret_password_12345"
    And I corrupt the authentication tag of the locked blob
    When I attempt to unlock the corrupted blob
    Then I should receive an authentication error
    And the error message should not contain "super_secret_password_12345"

  Scenario: Error messages do not contain key material
    Given I lock "secret data" with key A
    And I have a different key B
    When I attempt to unlock the blob with key B
    Then I should receive an authentication error
    And the error message should not contain key A's private key bytes
    And the error message should not contain key B's private key bytes

  Scenario: Modified ciphertext does not leak partial plaintext
    Given I lock a 1024-byte secret
    And I flip a single bit in the ciphertext
    When I attempt to unlock the modified blob
    Then I should receive an authentication error
    And the error should not contain any portion of the original plaintext

  Scenario: Exceptions during serialization do not leak data
    Given a complex data structure with secrets
    When serialization fails during lock operation
    Then the exception should not contain the secret values
    And the exception should only contain safe error descriptions
