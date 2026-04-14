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

  @doc """
  Creates a new table.

  Errors: `{:already_exists, name}` (`repo.table/already_exists`).
  """
  @callback create(name :: atom(), opts :: keyword()) :: {:ok, term()} | {:error, term()}

  @doc """
  Destroys a table and all its data.

  Errors: `{:not_found, name}` (`repo.table/not_found`).
  """
  @callback drop(name :: atom()) :: :ok | {:error, term()}

  @doc """
  Returns all keys in the table.

  Errors: `{:not_found, name}` (`repo.table/not_found`).
  """
  @callback keys(name :: atom()) :: {:ok, [term()]} | {:error, term()}

  @doc """
  Returns the number of entries in the table.

  Errors: `{:not_found, name}` (`repo.table/not_found`).
  """
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
