# Contexts

**TODO: Add description**

**Comn.Contexts** — _Operational context and propagation_

> “What request/trace/session/user/env am I in?”

**Why**: Errors and Events are both better when they include structured context. Think `request_id`, `actor_id`, `trace_id`, `env`, `zone`, `module`, etc.

**Pattern**:

```elixir
Comn.Context.get(:request_id)
Comn.Context.put(:user_id, "abc123")
Comn.Context.with(%{trace_id: "xyz"}, fn -> ... end)
```

**Why it matters**:

- Every `Comn.Error` and `Comn.Event` should be able to auto-populate from context

- You can pipe this into logs, metrics, or telemetry without rewriting every callsite

➡ Think of this as your **local carrier of system identity + causality**. Works like `Process.put/2` or OpenTelemetry’s baggage, but without the ceremony.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `contexts` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:contexts, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/context>.

