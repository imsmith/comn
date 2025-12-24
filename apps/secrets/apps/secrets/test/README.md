# Secrets Tests

This directory contains security-focused tests for the Comn.Secrets subsystem.

## Structure

```
test/
├── features/                        # Gherkin feature files (BDD specs)
│   ├── key_validation.feature
│   ├── leakage_prevention.feature
│   ├── authentication.feature
│   ├── nonce_uniqueness.feature
│   └── container_integrity.feature
├── comn/secrets/
│   ├── security_test_case.ex       # Shared security tests
│   └── example_implementation_test.exs
└── test_helper.exs
```

## Test Philosophy

The Secrets subsystem uses **security-first testing**:

1. **Gherkin Features** - Define WHAT the security requirements are (human-readable specs)
2. **SecurityTestCase** - Define HOW to verify those requirements (executable tests)
3. **Implementation Tests** - Verify specific backends meet all requirements

Any implementation of `Comn.Secrets` MUST pass all tests in `SecurityTestCase`.

## Gherkin Features

Feature files describe security requirements in natural language using the Given/When/Then format:

### key_validation.feature
Ensures implementations reject malformed or weak keys:
- Wrong key sizes for algorithms
- Missing private keys
- Algorithm/size mismatches

### leakage_prevention.feature  
Ensures error messages never contain sensitive data:
- No plaintext in errors
- No key material in exceptions
- No partial plaintext on authentication failures

### authentication.feature
Ensures AEAD tag verification detects tampering:
- Corrupted tags rejected
- Modified ciphertext rejected
- Metadata tampering detected

### nonce_uniqueness.feature
Ensures nonces are never reused (CRITICAL for AEAD):
- Same plaintext produces different ciphertexts
- Nonces are cryptographically random
- No deterministic encryption

### container_integrity.feature
Ensures containers protect collection structure:
- Containers are encrypted, not just bundled
- Blob reordering detected
- Deletion/injection attacks prevented

## Using SecurityTestCase

When you implement `Comn.Secrets` for a backend (e.g., Local, AWS KMS, Vault):

```elixir
defmodule MyApp.Secrets.LocalTest do
  use ExUnit.Case
  use Comn.Secrets.SecurityTestCase, implementation: MyApp.Secrets.Local
  
  # All security tests are automatically included
  
  # Add backend-specific tests here
  describe "Local backend specifics" do
    test "uses Erlang :crypto module" do
      # ...
    end
  end
end
```

## Running Tests

```bash
# Run all secrets tests
mix test apps/secrets/test

# Run only security tests
mix test apps/secrets/test/comn/secrets/security_test_case.ex

# Run with verbose output
mix test --trace

# Run specific test
mix test apps/secrets/test/comn/secrets/security_test_case.ex:42
```

## Test Requirements

All implementations MUST pass these tests before being considered secure:

- ✅ Key validation (5 tests)
- ✅ Leakage prevention (3 tests)
- ✅ Authentication tag verification (4 tests)
- ✅ Nonce uniqueness (3 tests)
- ✅ Container integrity (5 tests)

**Total: 20 required security tests**

Failure of any test indicates a critical security vulnerability.

## Adding New Security Tests

When adding new security requirements:

1. **Update Gherkin feature** - Add scenario to appropriate .feature file
2. **Add ExUnit test** - Implement test in SecurityTestCase
3. **Document in behavior** - Update Comn.Secrets moduledoc
4. **Reference in data model** - Update comn-secret.yang comments

Example:

```gherkin
# In features/key_validation.feature
Scenario: Reject keys with weak entropy
  Given a key with only 64 bits of entropy
  When I attempt to lock data
  Then I should receive error :weak_key
```

```elixir
# In security_test_case.ex
test "rejects keys with weak entropy" do
  weak_key = %Key{
    algorithm: :ed25519,
    public: <<0, 0, 0, 0, 0, 0, 0, 0>>,  # Weak!
    private: <<1, 1, 1, 1, 1, 1, 1, 1>>
  }
  
  assert {:error, :weak_key} = @impl.lock("data", weak_key)
end
```

## Security Vulnerabilities to Test For

Current tests cover:

- ❌ Nonce reuse (catastrophic with AEAD)
- ❌ Weak key acceptance
- ❌ Plaintext leakage in errors
- ❌ Key material leakage
- ❌ Tag verification bypass
- ❌ Metadata tampering
- ❌ Container structure manipulation
- ❌ Deterministic encryption

Future tests should cover:

- ⚠️ Timing attacks (constant-time comparison)
- ⚠️ Side-channel leaks (cache timing)
- ⚠️ Memory disclosure (GC not zeroing)
- ⚠️ Deserialization attacks (unsafe binary_to_term)

## References

- Gherkin: https://cucumber.io/docs/gherkin/
- ExUnit: https://hexdocs.pm/ex_unit/
- AEAD Security: https://tools.ietf.org/html/rfc5116
- Nonce Reuse: https://www.youtube.com/watch?v=JQILAkBfZ4s (Forbidden Attack)
