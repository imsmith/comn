defmodule Comn.Repo.Queue do
  @moduledoc """
  Durable, crash-safe FIFO/LIFO job queues.

  Public, backend-agnostic facade. Callers always go through this module;
  backends (`Mem`, `SQLite`) are private and selected via the `:backend`
  option to `open/2`. The same code works on either backend.

  Crash safety is handled inside `pop/2`: if the callback raises or the
  caller process exits, the popped item is returned to the queue so a
  later worker can retry it.

  ## Examples

      iex> Comn.Repo.Queue.look() |> String.starts_with?("Queue")
      true
  """

  @behaviour Comn

  alias Comn.Errors.Registry, as: ErrReg
  alias Comn.Repo.Queue.Handle

  @typedoc "Opaque queue handle. Treat as a black box."
  @type t :: Handle.t()

  @backends %{mem: Comn.Repo.Queue.Mem, sqlite: Comn.Repo.Queue.SQLite}
  @disciplines [:fifo, :lifo]

  # ---- lifecycle ----

  @doc """
  Opens a queue.

  Options:

    * `:backend`    — `:mem` (default) or `:sqlite`. May also be a module
                      implementing `Comn.Repo.Queue.Backend`.
    * `:discipline` — `:fifo` (default) or `:lifo`.
    * `:path`       — required for `:sqlite`; absolute path to the queue file.

  All other options are passed to the backend.
  """
  @spec open(term(), keyword()) :: {:ok, t()} | {:error, Comn.Errors.ErrorStruct.t()}
  def open(name, opts \\ []) do
    with {:ok, backend}    <- resolve_backend(Keyword.get(opts, :backend, :mem)),
         {:ok, discipline} <- resolve_discipline(Keyword.get(opts, :discipline, :fifo)),
         {:ok, state}      <- backend.open(name, opts) do
      {:ok, %Handle{backend: backend, state: state, name: name, discipline: discipline}}
    else
      {:error, %{code: _} = err} ->
        {:error, err}

      {:error, reason} ->
        {:error, ErrReg.error!("repo.queue/open_failed", field: inspect(reason))}
    end
  end

  @spec close(t()) :: :ok
  def close(%Handle{backend: b, state: s}), do: b.close(s)

  # ---- operations ----

  @spec push(t(), term()) :: :ok | {:error, Comn.Errors.ErrorStruct.t()}
  def push(%Handle{backend: b, state: s}, item) do
    case b.push(s, item) do
      :ok -> :ok
      {:error, reason} -> {:error, wrap_backend_error(reason)}
    end
  end

  @doc """
  Atomically reserves the head item, runs `fun.(item)` synchronously, and
  acks on normal return. If `fun` raises, throws, or exits, the item is
  released back to the queue and the exception re-raised.

  Returns `{:ok, fun_result}` on success or `:empty` if the queue had no
  available items.
  """
  @spec pop(t(), (term() -> result)) :: {:ok, result} | :empty when result: var
  def pop(%Handle{backend: b, state: s} = q, fun) when is_function(fun, 1) do
    case b.reserve(s) do
      :empty ->
        :empty

      {:ok, {token, item}} ->
        try do
          result = fun.(item)
          :ok = b.ack(s, token)
          {:ok, result}
        rescue
          e ->
            _ = b.release(s, token)
            reraise e, __STACKTRACE__
        catch
          kind, reason ->
            _ = b.release(s, token)
            :erlang.raise(kind, reason, __STACKTRACE__)
        end

      {:error, reason} ->
        # Reserve failure is not the caller's bug; surface but do not raise.
        :empty
        |> tap(fn _ -> log_reserve_error(q, reason) end)
    end
  end

  @spec peek(t(), pos_integer()) :: [term()]
  def peek(%Handle{backend: b, state: s}, n \\ 1) when is_integer(n) and n > 0 do
    b.peek(s, n)
  end

  @spec size(t()) :: non_neg_integer()
  def size(%Handle{backend: b, state: s}), do: b.size(s)

  @spec find(t(), (term() -> boolean())) :: {:ok, term()} | :not_found
  def find(%Handle{backend: b, state: s}, fun) when is_function(fun, 1) do
    b.find(s, fun)
  end

  @spec remove(t(), (term() -> boolean())) :: {:ok, term()} | :not_found
  def remove(%Handle{backend: b, state: s}, fun) when is_function(fun, 1) do
    b.remove(s, fun)
  end

  # ---- @behaviour Comn ----

  @impl Comn
  def look,
    do: "Queue — durable, crash-safe FIFO/LIFO job queues with hidden reserve/ack"

  @impl Comn
  def recon do
    %{
      callbacks: [:open, :close, :push, :pop, :peek, :size, :find, :remove],
      backends:  Map.keys(@backends),
      type:      :facade
    }
  end

  @impl Comn
  def choices, do: %{backends: ["mem", "sqlite"], disciplines: ["fifo", "lifo"]}

  @impl Comn
  def act(%{action: :open, name: n, opts: o}), do: open(n, o)
  def act(%{action: :open, name: n}),          do: open(n, [])
  def act(_),                                  do: {:error, :unknown_action}

  # ---- internals ----

  defp resolve_backend(:mem),    do: {:ok, Comn.Repo.Queue.Mem}
  defp resolve_backend(:sqlite), do: {:ok, Comn.Repo.Queue.SQLite}

  defp resolve_backend(mod) when is_atom(mod) do
    if Code.ensure_loaded?(mod) and function_exported?(mod, :reserve, 1) do
      {:ok, mod}
    else
      {:error, ErrReg.error!("repo.queue/invalid_opts",
                 field: "backend", suggestion: ":mem | :sqlite | implementing module")}
    end
  end

  defp resolve_backend(_),
    do: {:error, ErrReg.error!("repo.queue/invalid_opts", field: "backend")}

  defp resolve_discipline(d) when d in @disciplines, do: {:ok, d}

  defp resolve_discipline(_),
    do: {:error, ErrReg.error!("repo.queue/invalid_opts",
            field: "discipline", suggestion: ":fifo | :lifo")}

  defp wrap_backend_error(%_{code: _} = err), do: err
  defp wrap_backend_error(reason),
    do: ErrReg.error!("repo.queue/reserve_failed", field: inspect(reason))

  defp log_reserve_error(%Handle{name: n}, reason) do
    require Logger
    Logger.error("Comn.Repo.Queue reserve failed (queue=#{inspect(n)}): #{inspect(reason)}")
  end
end
