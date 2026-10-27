defmodule Comn.Repo.Lifecycle do
  @moduledoc """
  The open/close/drop lifecycle shared by every handle-based shape.

  A shape (`Comn.Repo.Table`, `Comn.Repo.Stream`, ...) supplies
  `backends/0`, a map of short names to backend modules. By convention
  its backend contract is `<Shape>.Backend` and its error codes are
  prefixed `repo.<shape>`; both are derived here so a shape adds no
  lifecycle code of its own beyond delegating to this module.
  """

  alias Comn.Errors.Registry, as: ErrReg
  alias Comn.Repo.Handle

  @doc """
  Resolves `opts[:backend]`, opens it, and wraps the result in a `Handle`.

  Errors: `repo.<shape>/invalid_opts`, plus whatever the backend returns.
  """
  @spec open(module(), term(), keyword()) :: {:ok, Handle.t()} | {:error, term()}
  def open(shape, name, opts) when is_list(opts) do
    with {:ok, backend} <- resolve_backend(shape, Keyword.fetch!(opts, :backend)),
         {:ok, state} <- backend.open(name, opts) do
      {:ok, %Handle{shape: shape, backend: backend, state: state, name: name}}
    end
  end

  @doc "Releases the handle. Idempotent."
  @spec close(Handle.t()) :: :ok
  def close(%Handle{backend: b, state: s}), do: b.close(s)

  @doc "Deletes the resource and everything in it. Idempotent."
  @spec drop(Handle.t()) :: :ok
  def drop(%Handle{backend: b, state: s}), do: b.drop(s)

  @doc """
  Re-binds a verb result that carries new backend state into the handle.

  Value-shaped backends (a graph, a file) return `{:ok, new_state}` from
  mutating verbs; `rebind/2` turns that into `{:ok, new_handle}` and
  passes every other result through untouched.
  """
  @spec rebind(Handle.t(), term()) :: term()
  def rebind(%Handle{} = h, {:ok, state}), do: {:ok, %Handle{h | state: state}}
  def rebind(_h, other), do: other

  @doc """
  Turns a short name from `shape.backends/0`, or a module implementing
  `<Shape>.Backend`, into a loaded backend module.

  Errors: `repo.<shape>/invalid_opts` when the key is unknown, the module
  is not loadable (an optional dependency is missing), or the module does
  not declare the shape's backend behaviour.
  """
  @spec resolve_backend(module(), atom()) ::
          {:ok, module()} | {:error, Comn.Errors.ErrorStruct.t()}
  def resolve_backend(shape, key) when is_atom(key) do
    backends = shape.backends()
    mod = Map.get(backends, key, key)

    cond do
      not Map.has_key?(backends, key) and not Code.ensure_loaded?(mod) ->
        invalid(shape, backends, [])

      not Code.ensure_loaded?(mod) ->
        invalid(shape, backends, message: "#{inspect(key)} needs its optional dependency")

      not implements?(mod, Module.concat(shape, Backend)) ->
        invalid(shape, backends,
          message: "#{inspect(mod)} does not implement #{inspect(shape)}.Backend"
        )

      true ->
        {:ok, mod}
    end
  end

  def resolve_backend(shape, _), do: invalid(shape, shape.backends(), [])

  defp invalid(shape, backends, extra) do
    suggestion = backends |> Map.keys() |> Enum.map_join(" | ", &inspect/1)

    {:error,
     ErrReg.error!(
       "#{prefix(shape)}/invalid_opts",
       [field: "backend", suggestion: suggestion] ++ extra
     )}
  end

  defp implements?(mod, behaviour) do
    mod.module_info(:attributes)
    |> Keyword.get_values(:behaviour)
    |> List.flatten()
    |> Enum.member?(behaviour)
  end

  # Comn.Repo.Table -> "repo.table"
  defp prefix(shape) do
    shape |> Module.split() |> Enum.drop(1) |> Enum.map_join(".", &String.downcase/1)
  end
end
