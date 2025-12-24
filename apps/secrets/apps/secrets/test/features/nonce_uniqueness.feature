Feature: Nonce Uniqueness
  As a security-conscious developer
  I want nonces to be unique for every encryption
  So that AEAD cipher security is maintained

  Background:
    Given a Comn.Secrets implementation
    And a valid Ed25519 key

  Scenario: Same plaintext produces different ciphertexts
    Given I lock the plaintext "identical secret data"
    When I lock the same plaintext again
    Then the nonces should be different
    And the ciphertexts should be different
    Because deterministic encryption is catastrophic with AEAD ciphers

  Scenario: Nonces are cryptographically random
    Given I lock "same plaintext" 100 times
    Then all 100 nonces should be unique
    And nonces should not be sequential
    And nonces should not be timestamp-based
    And nonces should have high entropy

  Scenario: Nonces have sufficient length
    Given I lock "secret data"
    When I inspect the nonce
    Then the nonce should be at least 12 bytes
    For AES-GCM and ChaCha20-Poly1305 security

  Scenario: Different plaintexts produce different nonces
    Given I lock "secret 1"
    And I lock "secret 2"
    And I lock "secret 3"
    Then all three nonces should be different
    And all three ciphertexts should be different
