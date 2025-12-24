Feature: Container Integrity
  As a security-conscious developer
  I want containers to protect collection structure
  So that blob reordering, deletion, and injection attacks are prevented

  Background:
    Given a Comn.Secrets implementation
    And a valid Ed25519 key

  Scenario: Wrap returns LockedBlob, not Container
    Given I lock three individual secrets
    When I wrap them in a container
    Then the result should be a LockedBlob
    Not a Container struct
    Because containers must be encrypted, not just bundled

  Scenario: Unwrap takes LockedBlob and returns list of blobs
    Given I wrap three locked blobs in a container
    When I unwrap the container LockedBlob
    Then I should receive a list of LockedBlobs
    And the list should contain 3 elements
    And they should be in the original order

  Scenario: Container preserves blob order
    Given I lock "secret1", "secret2", "secret3" in that order
    And I wrap them in a container
    When I unwrap the container
    And I unlock each blob
    Then the plaintexts should be "secret1", "secret2", "secret3" in that order

  Scenario: Tampering with container ciphertext is detected
    Given I wrap three blobs in a container
    And I corrupt the container's ciphertext
    When I attempt to unwrap
    Then I should receive error :authentication_failed
    Because the container's tag covers the entire structure

  Scenario: Cannot inject blobs into container
    Given I wrap two blobs in a container
    When an attacker modifies the container ciphertext
    Then unwrap should fail with authentication error
    Because the tag covers the number and order of blobs

  Scenario: Cannot delete blobs from container
    Given I wrap three blobs in a container
    When an attacker tries to remove one blob by modifying ciphertext
    Then unwrap should fail with authentication error
    Because the tag covers the complete collection structure

  Scenario: Cannot reorder blobs in container
    Given I wrap [blob1, blob2, blob3] in a container
    When an attacker tries to reorder by modifying ciphertext
    Then unwrap should fail with authentication error
    Because the serialized structure is authenticated

  Scenario: Cannot tamper with container metadata
    Given I wrap blobs with metadata %{env: "production"}
    When an attacker modifies the ciphertext to change metadata
    Then unwrap should fail with authentication error
    Because container metadata is part of the authenticated ciphertext
