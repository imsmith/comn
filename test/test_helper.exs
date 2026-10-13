# EventBus Registry, Events.Registry, EventLog, and error code discovery
# are all started by Comn.Supervisor via Comn.Application.

# Exclude Vault integration tests by default unless VAULT_TOKEN is set
# Exclude spatial phases that aren't implemented yet
exclude = [:phase1, :phase2, :phase3, :phase4]
exclude = if System.get_env("VAULT_TOKEN"), do: exclude, else: [:vault_integration | exclude]
# Exclude NATS JetStream integration tests unless NATS_URL is set (e.g. nats://127.0.0.1:4222)
exclude = if System.get_env("NATS_URL"), do: exclude, else: [:nats | exclude]

ExUnit.start(exclude: exclude)
