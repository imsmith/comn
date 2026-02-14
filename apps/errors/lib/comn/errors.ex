defmodule Comn.Errors do
  @moduledoc """
  Error handling utilities for wrapping and categorizing errors.
  """

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
end
