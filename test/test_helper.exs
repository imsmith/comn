# EventBus Registry, Events.Registry, EventLog, and error code discovery
# are all started by Comn.Supervisor via Comn.Application.

# Exclude Vault integration tests by default unless VAULT_TOKEN is set
# Exclude spatial phases that aren't implemented yet
exclude = [:phase1, :phase2, :phase3, :phase4]
exclude = if System.get_env("VAULT_TOKEN"), do: exclude, else: [:vault_integration | exclude]

ExUnit.start(exclude: exclude)
