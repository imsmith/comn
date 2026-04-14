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

  @doc "Wraps any term into an ErrorStruct via the Comn.Error protocol."
  @spec wrap(term()) :: ErrorStruct.t()
  def wrap(term) do
    Comn.Error.to_error(term)
  end

  @doc "Creates an ErrorStruct with the given category as the reason."
  @spec new(atom(), String.t(), String.t() | nil, String.t() | nil) :: ErrorStruct.t()
  def new(category, message, field \\ nil, suggestion \\ nil)
      when category in @categories do
    ErrorStruct.new(to_string(category), field, message, suggestion)
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
  def act(%{action: :wrap, term: term}), do: {:ok, wrap(term)}
  def act(%{action: :categorize, reason: reason}), do: {:ok, categorize(reason)}
  def act(%{action: :new, category: cat, message: msg} = input) do
    {:ok, new(cat, msg, Map.get(input, :field), Map.get(input, :suggestion))}
  end
  def act(_input), do: {:error, :unknown_action}
end
