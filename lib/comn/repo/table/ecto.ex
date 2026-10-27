if Code.ensure_loaded?(Ecto.Repo) do
  defmodule Comn.Repo.Table.Ecto do
    @moduledoc """
    `Comn.Repo.Table` backend over any Ecto adapter.

    Four properties:

    1. **Every mutation is a saga.** `set` and `delete` run as a
       transaction with an upsert. Whether it commits or rolls back, a
       system event is broadcast on `Comn.EventBus` topic `"comn.repo.table"`
       (`repo.table.set` / `repo.table.delete`, `data.status` `:ok` or
       `:failed`). A rolled-back set returns `repo.table/set_failed`.
    2. **Every mutation is against a schema.** `schema: MyApp.Row` names the
       Ecto schema the data is cast into and upserted on its primary key.
       An event's `data` becomes the row; its headers fill same-named
       fields. The default is `Comn.Repo.Table.Ecto.EventRow`, the event
       itself, in a table named `comn_<table>` so it never collides with a
       consumer schema's source.
    3. **No migrations.** The schema module is the declaration; the first
       use of a schema against a repo converges the database to it through
       the adapter's DDL (create table and columns if they do not exist).
       Nothing is versioned.
    4. **The repository is configuration.** `ecto: [adapter: Ecto.Adapters.Postgres, url: ...]`,
       `ecto: "repo.exs"`, or `repo: MyApp.Repo`. Ecto fixes the adapter
       when a repo module is compiled, so Comn compiles one per
       configuration at runtime and starts it under its own supervisor.

    Reads (`get`, `keys`, `count`, `observe`) take the same `schema:`.
    Terms cross into columns through `Comn.Repo.Table.Ecto.Term` on the
    default schema; a consumer schema's column types do the casting.
    """

    @behaviour Comn.Repo.Table.Backend

    import Ecto.Query, only: [from: 2]

    alias Comn.Errors.Registry, as: ErrReg
    alias Comn.Events.EventStruct
    alias Comn.Repo.Table.Ecto.EventRow
    alias Comn.Repo.Table.Ecto.Repos

    @topic "comn.repo.table"

    # state: %{repo: module, name: atom, source: "comn_<name>"}

    @impl true
    def open(name, opts) do
      with {:ok, repo} <- Repos.ensure(opts) do
        {:ok, %{repo: repo, name: name, source: "comn_" <> Atom.to_string(name)}}
      end
    end

    @impl true
    def close(_state), do: :ok

    # Deletes the rows of the default table. Tables made by converge stay;
    # destructive DDL is not Comn's to run.
    @impl true
    def drop(%{repo: repo, source: source}) do
      if converged?(repo, source), do: repo.delete_all({source, EventRow})
      :ok
    end

    @doc "The Ecto repo behind a handle's state."
    @spec repo(map()) :: module()
    def repo(%{repo: repo}), do: repo

    # ---- reads ----

    @impl true
    def get(state, key, opts) do
      with {:ok, schema, source, pk} <- target(state, opts),
           :ok <- converge(state.repo, schema, source) do
        case state.repo.one(from(r in {source, schema}, where: field(r, ^pk) == ^key)) do
          nil -> {:error, ErrReg.error!("repo.table/not_found", field: inspect(key))}
          row -> {:ok, to_value(schema, row)}
        end
      end
    end

    @impl true
    def keys(state, opts) do
      with {:ok, schema, source, pk} <- target(state, opts),
           :ok <- converge(state.repo, schema, source) do
        {:ok, state.repo.all(from(r in {source, schema}, select: field(r, ^pk)))}
      end
    end

    @impl true
    def count(state, opts) do
      with {:ok, schema, source, _pk} <- target(state, opts),
           :ok <- converge(state.repo, schema, source) do
        {:ok, state.repo.aggregate({source, schema}, :count)}
      end
    end

    @impl true
    def observe(state, opts) do
      with {:ok, schema, source, pk} <- target(state, opts),
           :ok <- converge(state.repo, schema, source) do
        for row <- state.repo.all({source, schema}),
            do: {Map.fetch!(row, pk), to_value(schema, row)}
      end
    end

    # ---- sagas ----

    @impl true
    def set(%{repo: repo, name: name} = state, key, value, opts) do
      with {:ok, schema, source, pk} <- target(state, opts),
           :ok <- converge(repo, schema, source) do
        attrs = attrs(schema, name, key, value)

        changeset =
          Ecto.Changeset.cast(
            Ecto.put_meta(struct(schema), source: source),
            attrs,
            schema.__schema__(:fields)
          )

        repo
        |> saga(fn -> upsert(repo, changeset, pk) end)
        |> outcome("repo.table.set", "repo.table/set_failed", name, key, schema)
      end
    end

    @impl true
    def delete(%{repo: repo, name: name} = state, key, opts) do
      with {:ok, schema, source, pk} <- target(state, opts),
           :ok <- converge(repo, schema, source) do
        repo
        |> saga(fn -> delete_row(repo, source, schema, pk, key) end)
        |> outcome("repo.table.delete", "repo.table/delete_failed", name, key, schema)
      end
    end

    # Every saga ends in an event and either :ok or the verb's failure code.
    defp outcome({:ok, _}, topic, _code, name, key, schema) do
      emit(topic, name, key, schema, :ok)
      :ok
    end

    defp outcome({:error, reason}, topic, code, name, key, schema) do
      emit(topic, name, key, schema, :failed)
      {:error, ErrReg.error!(code, field: inspect(key), message: explain(reason))}
    end

    defp upsert(repo, changeset, pk) do
      case repo.insert(changeset, on_conflict: {:replace_all_except, [pk]}, conflict_target: [pk]) do
        {:ok, row} -> row
        {:error, cs} -> repo.rollback(cs)
      end
    end

    defp delete_row(repo, source, schema, pk, key),
      do: repo.delete_all(from(r in {source, schema}, where: field(r, ^pk) == ^key))

    # A saga boundary: whatever happens inside, the caller gets {:ok, _} or
    # {:error, reason}, and the transaction has rolled back on error. A
    # database exception (bad column, constraint, lost connection) is a
    # failed saga, not a crash in the caller.
    defp saga(repo, fun) do
      repo.transaction(fun)
    rescue
      e -> {:error, e}
    end

    # ---- converge: the schema module is the declaration ----

    # ponytail: creates the table and its columns if absent; does not add
    # columns to an existing table. Teach it ALTER when a schema grows.
    defp converge(repo, schema, source) do
      if converged?(repo, source, schema) do
        :ok
      else
        pk = schema.__schema__(:primary_key)

        columns =
          for f <- schema.__schema__(:fields) do
            {:add, f, ddl_type(schema.__schema__(:type, f)), [primary_key: f in pk]}
          end

        table = %Ecto.Migration.Table{name: source, primary_key: false}
        meta = Ecto.Adapter.lookup_meta(repo)

        case repo.__adapter__().execute_ddl(meta, {:create_if_not_exists, table, columns}, []) do
          {:ok, _} ->
            :persistent_term.put({__MODULE__, repo, source, schema}, true)
            :ok

          other ->
            {:error,
             ErrReg.error!("repo.table/invalid_schema",
               field: inspect(schema),
               message: inspect(other)
             )}
        end
      end
    end

    defp converged?(repo, source, schema \\ EventRow),
      do: :persistent_term.get({__MODULE__, repo, source, schema}, false)

    defp ddl_type({:array, t}), do: {:array, ddl_type(t)}
    defp ddl_type({:parameterized, _}), do: :string
    # a custom Ecto.Type declares its storage type in type/0
    defp ddl_type(t) when is_atom(t) do
      if Code.ensure_loaded?(t) and function_exported?(t, :type, 0), do: t.type(), else: t
    end

    # ---- internals ----

    defp target(%{source: default_source}, opts) do
      case Keyword.get(opts, :schema, EventRow) do
        EventRow ->
          {:ok, EventRow, default_source, :id}

        schema when is_atom(schema) ->
          with true <- Code.ensure_loaded?(schema) and function_exported?(schema, :__schema__, 1),
               [pk] <- schema.__schema__(:primary_key) do
            {:ok, schema, schema.__schema__(:source), pk}
          else
            _ -> {:error, ErrReg.error!("repo.table/invalid_schema", field: inspect(schema))}
          end

        other ->
          {:error, ErrReg.error!("repo.table/invalid_schema", field: inspect(other))}
      end
    end

    defp attrs(EventRow, _name, _key, %EventStruct{} = e), do: EventRow.attrs_for_event(e)
    defp attrs(EventRow, name, key, value), do: EventRow.attrs_for_value(name, key, value)

    defp attrs(schema, _name, key, %EventStruct{} = e) do
      [pk] = schema.__schema__(:primary_key)
      headers = e |> Map.from_struct() |> Map.take(schema.__schema__(:fields))
      headers |> Map.merge(Map.new(e.data)) |> Map.put(pk, key)
    end

    defp attrs(schema, _name, key, value) when is_map(value) do
      [pk] = schema.__schema__(:primary_key)
      value |> Map.new() |> Map.put(pk, key)
    end

    defp attrs(schema, _name, key, value) do
      [pk] = schema.__schema__(:primary_key)
      %{pk => key, :data => value}
    end

    defp to_value(EventRow, row), do: EventRow.to_value(row)
    defp to_value(_schema, row), do: row

    defp emit(topic, name, key, schema, status) do
      Comn.EventBus.broadcast(
        @topic,
        EventStruct.new(
          :system,
          topic,
          %{name: name, key: key, schema: schema, status: status},
          __MODULE__
        )
      )
    end

    defp explain(%Ecto.Changeset{errors: errors}), do: "changeset: #{inspect(errors)}"
    defp explain(%{__exception__: true} = e), do: Exception.message(e)
    defp explain(other), do: inspect(other)
  end
end
