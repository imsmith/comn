if Code.ensure_loaded?(Ecto.Type) do
  defmodule Comn.Repo.Table.Ecto.Term do
    @moduledoc """
    An Ecto type that stores any Elixir term faithfully, as a binary column
    holding Erlang's deterministic external term format. Used for the
    columns of `Comn.Repo.Table.Ecto.EventRow` whose values are arbitrary
    terms (`id`, `data`, `tags`, `metadata`, ...), so an event round-trips
    exactly through any adapter.
    """

    use Ecto.Type

    @impl true
    def type, do: :binary

    @impl true
    def cast(term), do: {:ok, term}

    @impl true
    def dump(term), do: {:ok, :erlang.term_to_binary(term, [:deterministic])}

    @impl true
    def load(bin) when is_binary(bin), do: {:ok, Comn.Repo.decode_term(bin)}
    def load(_), do: :error
  end
end
