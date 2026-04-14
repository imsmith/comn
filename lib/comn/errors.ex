defmodule Comn.Errors do
  @moduledoc """
  Structured error handling: wrapping, categorization, and creation.

  Wraps arbitrary terms into `Comn.Errors.ErrorStruct` via the `Comn.Error`
  protocol, and categorizes error reasons into one of six buckets:
  `:validation`, `:persistence`, `:network`, `:auth`, `:internal`, `:unknown`.

  Also implements `@behaviour Comn` for uniform introspection.

  ## Examples

      iex> Comn.Errors.categorize("invalid_format")
      :validation

      iex> Comn.Errors.categorize("database_timeout")
      :persistence

      iex> Comn.Errors.categorize("connection_refused")
      :network

      iex> Comn.Errors.look()
      "Errors — wrap, categorize, and create structured errors"
  """

  @behaviour Comn

  alias Comn.Errors.ErrorStruct

  @categories [:validation, :persistence, :network, :auth, :internal, :unknown]

  @doc "Returns the list of known error categories."
  def categories, do: @categories

  @doc "Wraps any term into an ErrorStruct via the Comn.Error protocol, enriched with ambient context."
  @spec wrap(term()) :: {:ok, ErrorStruct.t()} | {:error, term()}
  def wrap(term) do
    case Comn.Error.to_error(term) do
      {:ok, error} -> {:ok, enrich(error)}
      {:error, _} = err -> err
    end
  end

  @doc "Creates an ErrorStruct with the given category as the reason, enriched with ambient context."
  @spec new(atom(), String.t(), String.t() | nil, String.t() | nil) :: ErrorStruct.t()
  def new(category, message, field \\ nil, suggestion \\ nil)
      when category in @categories do
    ErrorStruct.new(to_string(category), field, message, suggestion)
    |> enrich()
  end

  @doc """
  Enriches an `ErrorStruct` with ambient context fields.

  Pulls `request_id`, `trace_id`, and `correlation_id` from `Comn.Contexts`
  if the calling process has a context set. Existing values on the struct
  are not overwritten.
  """
  @spec enrich(ErrorStruct.t()) :: ErrorStruct.t()
  def enrich(%ErrorStruct{} = error) do
    case Comn.Contexts.get() do
      nil ->
        error

      ctx ->
        %{error |
          request_id: error.request_id || ctx.request_id,
          trace_id: error.trace_id || ctx.trace_id,
          correlation_id: error.correlation_id || ctx.correlation_id
        }
    end
  end

  @doc "Categorizes an error reason string into a known category atom."
  @spec categorize(String.t() | atom()) :: atom()
  def categorize(reason) when is_atom(reason), do: categorize(to_string(reason))

  def categorize(reason) when is_binary(reason) do
    reason_down = String.downcase(reason)

    cond do
      match_any?(reason_down, ~w(valid invalid required missing format type)) -> :validation
      match_any?(reason_down, ~w(database db persist save write read query timeout)) -> :persistence
      match_any?(reason_down, ~w(network connect socket http dns unreachable refused)) -> :network
      match_any?(reason_down, ~w(auth login password credential token permission denied forbidden unauthorized)) -> :auth
      true -> :internal
    end
  end

  def categorize(_), do: :unknown

  defp match_any?(str, keywords) do
    Enum.any?(keywords, &String.contains?(str, &1))
  end

  # Comn callbacks

  @impl Comn
  def look, do: "Errors — wrap, categorize, and create structured errors"

  @impl Comn
  def recon do
    %{
      categories: @categories,
      struct: Comn.Errors.ErrorStruct,
      type: :facade
    }
  end

  @impl Comn
  def choices do
    %{categories: Enum.map(@categories, &to_string/1)}
  end

  @impl Comn
  def act(%{action: :wrap, term: term}), do: wrap(term)
  def act(%{action: :categorize, reason: reason}), do: {:ok, categorize(reason)}
  def act(%{action: :new, category: cat, message: msg} = input) do
    {:ok, new(cat, msg, Map.get(input, :field), Map.get(input, :suggestion))}
  end
  def act(_input), do: {:error, :unknown_action}
end
