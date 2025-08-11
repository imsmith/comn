# Comn

Comn is a set of tools for building elixir applications that provides a consistent and easy-to-use interface for common infrastructure tasks such as error handling, event handling, secrets management, repository management, infrastructure interaction, and context management.

# Features
- **Error Handling**: the Comn.Events module provides a consistent way to handle errors across your application.
- **Event Handling**: the Comn.Events module allows you to define and handle events in a consistent way.
- **Secrets Management**: the Comn.Secrets module provides a way to manage secrets in your application.
- **Repository Management**: the Comn.Repo module provides a way to manage repositories in your application.
- **Infrastructure Interaction**: the Comn.Infra modules provides a way to interact with infrastructure in a consistent way.
- **Context Management**: The Comn.Contexts modules provides a way to manage contexts in your application.


# Installation

To install Comn, add it to your `mix.exs` file:

```elixir
defp deps do
  [
    {:comn, "~> 0.1.0"}
  ]
end
```

Then run `mix deps.get` to fetch the dependency.

# Usage
To use Comn, you can start by defining your application structure and then use the provided modules to handle errors, events, secrets, repositories, infrastructure, and contexts.

# Example
