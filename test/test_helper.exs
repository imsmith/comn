Code.require_file("support/security_test_case.ex", __DIR__)

# Start the Registry that EventBus depends on
{:ok, _} = Registry.start_link(keys: :duplicate, name: Comn.EventBus)

# Exclude Vault integration tests by default unless VAULT_TOKEN is set
# Exclude spatial phases that aren't implemented yet
exclude = [:phase1, :phase2, :phase3, :phase4]
exclude = if System.get_env("VAULT_TOKEN"), do: exclude, else: [:vault_integration | exclude]

ExUnit.start(exclude: exclude)
