Feature: Authentication Tag Verification
  As a security-conscious developer
  I want all ciphertext to be authenticated
  So that tampering with locked blobs is detected

  Background:
    Given a Comn.Secrets implementation
    And a valid Ed25519 key

  Scenario: Reject locked blob with corrupted tag
    Given I lock "secret data"
    And I corrupt the authentication tag
    When I attempt to unlock the blob
    Then I should receive error :authentication_failed
    And no plaintext should be returned

  Scenario: Reject locked blob with modified ciphertext
    Given I lock "secret data"
    And I flip one bit in the ciphertext
    When I attempt to unlock the modified blob
    Then I should receive error :authentication_failed
    And no plaintext should be returned

  Scenario: Reject locked blob with modified metadata
    Given I lock "secret data" with metadata %{env: "production"}
    And I change the metadata to %{env: "development"}
    When I attempt to unlock the blob
    Then I should receive error :authentication_failed
    Because metadata should be authenticated via AEAD associated data

  Scenario: Reject locked blob with wrong key
    Given I lock "secret data" with key A
    And I have a different key B
    When I attempt to unlock with key B
    Then I should receive an authentication error
    And no plaintext should be returned

  Scenario: Accept unmodified locked blob
    Given I lock "secret data"
    When I unlock with the same key
    Then I should receive success
    And the plaintext should be "secret data"
