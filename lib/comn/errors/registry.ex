defmodule Comn.Errors.Registry do
  @moduledoc """
  Compile-time error code registry with runtime lookup.

  Modules declare their error codes with `register_error/3`, which accumulates
  definitions at compile time and generates a `__errors__/0` function on the
  declaring module. At runtime, call `discover/0` to index all loaded modules,
  or `register_module/1` for individual modules.

  ## Code format

  Error codes follow a strict `namespace/error_name` format:

  - **Namespace** — lowercase, dot-separated segments (e.g. `auth`,
    `repo.table`, `myapp.billing.stripe`)
  - **Error name** — lowercase, underscore-separated (e.g. `invalid_key`,
    `not_found`)
  - Exactly one `/` separating namespace from error name

  Valid: `secrets/invalid_key`, `repo.table/not_found`, `myapp.auth/expired_token`
  Invalid: `InvalidKey`, `auth/token/expired`, `auth/invalid-token`

  Codes are validated at compile time. Duplicate codes across modules are
  rejected at registration time.

  ## Declaring errors

      defmodule MyApp.Auth.Errors do
        use Comn.Errors.Registry

        register_error "auth/invalid_token",   :auth, message: "Token is invalid or expired"
        register_error "auth/expired_session",  :auth, message: "Session has expired", status: 401
        register_error "auth/forbidden",        :auth, message: "Insufficient permissions", status: 403
      end

  ## Runtime lookup

      Comn.Errors.Registry.discover()

      Comn.Errors.Registry.lookup("auth/invalid_token")
      #=> %{code: "auth/invalid_token", category: :auth, message: "Token is invalid or expired",
      #     status: nil, module: MyApp.Auth.Errors}

  ## Creating errors from codes

      Comn.Errors.Registry.error("auth/invalid_token")
      #=> %Comn.Errors.ErrorStruct{code: "auth/invalid_token", reason: "auth",
      #     message: "Token is invalid or expired", ...}

      Comn.Errors.Registry.error("auth/invalid_token", field: "authorization")
      #=> %Comn.Errors.ErrorStruct{code: "auth/invalid_token", field: "authorization", ...}

  ## Prefix queries

      Comn.Errors.Registry.codes_for_prefix("auth/")
      #=> ["auth/expired_session", "auth/forbidden", "auth/invalid_token"]

      Comn.Errors.Registry.codes_for_prefix("repo.")
      #=> ["repo.table/not_found", "repo.file/invalid_state"]
  """

  @persistent_term_key :comn_errors_registry

  @code_pattern ~r/^[a-z][a-z0-9]*(\.[a-z][a-z0-9]*)*\/[a-z][a-z0-9_]*$/

  # -- Compile-time macros --

  defmacro __using__(_opts) do
    quote do
      Module.register_attribute(__MODULE__, :registered_errors, accumulate: true)
      @before_compile Comn.Errors.Registry
      import Comn.Errors.Registry, only: [register_error: 3]
    end
  end

  @doc """
  Registers an error code at compile time.

  - `code` — `"namespace/error_name"` (validated against `#{inspect(@code_pattern)}`)
  - `category` — one of the `Comn.Errors.categories/0` atoms
  - `opts` — keyword list:
    - `:message` — default human-readable message
    - `:status` — HTTP status code (optional)
    - `:suggestion` — default suggestion text (optional)

  Raises `CompileError` if the code format is invalid.
  """
  defmacro register_error(code, category, opts) do
    unless is_binary(code) and Regex.match?(~r/^[a-z][a-z0-9]*(\.[a-z][a-z0-9]*)*\/[a-z][a-z0-9_]*$/, code) do
      raise CompileError,
        description: "invalid error code #{inspect(code)} — must match namespace/error_name " <>
          "(e.g. \"auth/invalid_token\", \"repo.table/not_found\")"
    end

    quote do
      @registered_errors %{
        code: unquote(code),
        category: unquote(category),
        message: unquote(Keyword.get(opts, :message)),
        status: unquote(Keyword.get(opts, :status)),
        suggestion: unquote(Keyword.get(opts, :suggestion)),
        module: __MODULE__
      }
    end
  end

  defmacro __before_compile__(env) do
    errors = Module.get_attribute(env.module, :registered_errors)

    quote do
      @doc false
      def __errors__, do: unquote(Macro.escape(errors))
    end
  end

  # -- Runtime API --

  @doc """
  Looks up an error definition by code.

  Returns the error map or `nil` if not found.
  """
  @spec lookup(String.t()) :: map() | nil
  def lookup(code) when is_binary(code) do
    get_index()[code]
  end

  @doc """
  Returns all registered error definitions.
  """
  @spec all() :: [map()]
  def all do
    get_index() |> Map.values()
  end

  @doc """
  Returns all registered error codes.
  """
  @spec codes() :: [String.t()]
  def codes do
    get_index() |> Map.keys() |> Enum.sort()
  end

  @doc """
  Returns all registered codes for a given category.
  """
  @spec codes_for(atom()) :: [String.t()]
  def codes_for(category) when is_atom(category) do
    get_index()
    |> Map.values()
    |> Enum.filter(&(&1.category == category))
    |> Enum.map(& &1.code)
    |> Enum.sort()
  end

  @doc """
  Creates a `Comn.Errors.ErrorStruct` from a registered error code.

  The struct is populated from the registry definition and enriched with
  ambient context (via `Comn.Errors.enrich/1`). Override any field via `opts`.

  Returns `{:ok, error_struct}` or `{:error, :unknown_code}`.
  """
  @spec error(String.t(), keyword()) :: {:ok, Comn.Errors.ErrorStruct.t()} | {:error, :unknown_code}
  def error(code, opts \\ []) when is_binary(code) do
    case lookup(code) do
      nil ->
        {:error, :unknown_code}

      defn ->
        error = %Comn.Errors.ErrorStruct{
          code: code,
          reason: to_string(defn.category),
          message: Keyword.get(opts, :message, defn.message),
          field: Keyword.get(opts, :field),
          suggestion: Keyword.get(opts, :suggestion, defn.suggestion)
        }

        {:ok, Comn.Errors.enrich(error)}
    end
  end

  @doc """
  Like `error/2` but returns the struct directly. Raises on unknown codes.

  Designed for use inside `{:error, ...}` tuples:

      {:error, Comn.Errors.Registry.error!("secrets/invalid_key")}
      {:error, Comn.Errors.Registry.error!("repo.table/not_found", field: name)}
  """
  @spec error!(String.t(), keyword()) :: Comn.Errors.ErrorStruct.t()
  def error!(code, opts \\ []) when is_binary(code) do
    case error(code, opts) do
      {:ok, err} -> err
      {:error, :unknown_code} -> raise ArgumentError, "unknown error code: #{inspect(code)}"
    end
  end

  @doc """
  Returns the HTTP status for a registered error code, or `nil`.
  """
  @spec http_status(String.t()) :: non_neg_integer() | nil
  def http_status(code) when is_binary(code) do
    case lookup(code) do
      nil -> nil
      defn -> defn.status
    end
  end

  @doc """
  Returns all registered codes whose code starts with `prefix`.
  """
  @spec codes_for_prefix(String.t()) :: [String.t()]
  def codes_for_prefix(prefix) when is_binary(prefix) do
    get_index()
    |> Map.keys()
    |> Enum.filter(&String.starts_with?(&1, prefix))
    |> Enum.sort()
  end

  @doc """
  Registers a single module's errors into the runtime index.

  The module must have been compiled with `use Comn.Errors.Registry`.
  Returns `{:error, {:duplicate_code, code, existing_module}}` if a code
  is already registered by a different module.
  """
  @spec register_module(module()) :: :ok | {:error, term()}
  def register_module(module) when is_atom(module) do
    if function_exported?(module, :__errors__, 0) do
      errors = module.__errors__()
      index = get_index()

      case find_duplicate(errors, index, module) do
        nil ->
          new_index =
            Enum.reduce(errors, index, fn defn, acc ->
              Map.put(acc, defn.code, defn)
            end)

          :persistent_term.put(@persistent_term_key, new_index)
          :ok

        {:duplicate, code, owner} ->
          {:error, {:duplicate_code, code, owner}}
      end
    else
      {:error, :not_a_registry_module}
    end
  end

  defp find_duplicate(errors, index, module) do
    Enum.find_value(errors, fn defn ->
      case Map.get(index, defn.code) do
        %{module: ^module} -> nil
        %{module: other} -> {:duplicate, defn.code, other}
        nil -> nil
      end
    end)
  end

  # Comn's own error modules. Ensures they are loaded before discovery
  # scans :code.all_loaded/0, since the BEAM only loads modules on first reference.
  @comn_error_modules [
    Comn.Secrets.Errors,
    Comn.Repo.Errors,
    Comn.Events.Errors
  ]

  @doc """
  Discovers and registers all loaded modules that declare error codes.

  Ensures Comn's built-in error modules are loaded first, then scans all
  loaded modules for `__errors__/0`. Call once at application boot or in
  test setup.
  """
  @spec discover() :: :ok
  def discover do
    Enum.each(@comn_error_modules, &Code.ensure_loaded!/1)

    for {module, _} <- :code.all_loaded(),
        function_exported?(module, :__errors__, 0) do
      register_module(module)
    end

    :ok
  end

  @doc """
  Resets the registry. Useful in tests.
  """
  @spec reset() :: :ok
  def reset do
    :persistent_term.put(@persistent_term_key, %{})
    :ok
  end

  defp get_index do
    :persistent_term.get(@persistent_term_key, %{})
  end
end
