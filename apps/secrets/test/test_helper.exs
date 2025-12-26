Code.require_file("support/security_test_case.ex", __DIR__)

# Exclude Vault integration tests by default unless VAULT_TOKEN is set
exclude = if System.get_env("VAULT_TOKEN"), do: [], else: [:vault_integration]

ExUnit.start(exclude: exclude)
