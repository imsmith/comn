defmodule Comn.Repo.Table do
  @moduledoc """
  Behaviour for table-style key-value repositories.

  Extends `Comn.Repo` with table lifecycle verbs: `create`, `drop`, `keys`,
  `count`. Currently backed by `Comn.Repo.Table.ETS`.

  Also implements `@behaviour Comn` for uniform introspection.

  ## Examples

      iex> Comn.Repo.Table.look()
      "Table — key-value repository behaviour (create, drop, keys, count)"

      iex> %{extends: Comn.Repo} = Comn.Repo.Table.recon()
  """

  @behaviour Comn

  @callback create(name :: atom(), opts :: keyword()) :: {:ok, term()} | {:error, term()}
  @callback drop(name :: atom()) :: :ok | {:error, term()}
  @callback keys(name :: atom()) :: {:ok, [term()]} | {:error, term()}
  @callback count(name :: atom()) :: {:ok, non_neg_integer()} | {:error, term()}

  @impl Comn
  def look, do: "Table — key-value repository behaviour (create, drop, keys, count)"

  @impl Comn
  def recon do
    %{
      callbacks: [:create, :drop, :keys, :count],
      extends: Comn.Repo,
      type: :behaviour
    }
  end

  @impl Comn
  def choices do
    %{implementations: ["ETS"]}
  end

  @impl Comn
  def act(_input), do: {:error, :behaviour_only}
end
