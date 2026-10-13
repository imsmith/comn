defmodule Comn.Repo.Stream.JetStream do
  @moduledoc """
  NATS JetStream implementation of `Comn.Repo.Stream`.

  Each Comn stream maps to one JetStream stream (see `js_stream_name/1`)
  carrying the single subject `comn.stream.<name>`. The offset **is**
  JetStream's stream sequence, so it is an integer starting at 1 and the
  Mem/SQLite consumer recipes carry over unchanged.

  - `append/2` publishes and waits for the PubAck; the ack's `seq` is the offset.
  - `read/3`, `head/1`, `tail/1` use stream info and direct message get.
  - `subscribe/2` creates one ephemeral push consumer per open stream on
    first use and fans its deliveries out to local subscribers, taking the
    offset from the `$JS.ACK` reply subject.
  - `commit/3` / `position/2` keep one key per stream+group in the KV
    bucket `comn_stream_groups`.

  One local GenServer per open stream, registered under the stream name,
  holds the connection and the consumer subscription. It is not linked to
  the opener; `close/1` stops it (server state stays), `drop/1` also
  deletes the JetStream stream. `start_link/1` is the supervisor entry.

  Requires a running `Gnat` connection, passed as `conn:` to `open/2`.
  See `test/stream_jetstream_test.exs` for the podman one-liner.
  """

  @behaviour Comn
  @behaviour Comn.Repo
  @behaviour Comn.Repo.Stream

  use GenServer

  alias Comn.Errors.Registry, as: ErrReg
  alias Comn.Events.EventStruct
  alias Gnat.Jetstream.API.Consumer
  alias Gnat.Jetstream.API.KV
  alias Gnat.Jetstream.API.Message
  alias Gnat.Jetstream.API.Stream, as: JS

  @registry Comn.EventBus
  @bucket "comn_stream_groups"

  # Lifecycle

  @doc """
  Opens the stream under `name` on the JetStream server behind `opts[:conn]`
  (a `Gnat` connection name or pid), creating the server stream if needed.

  Errors: `repo.stream/invalid_opts`, `repo.stream/already_exists`,
  `repo.stream/backend_error`.
  """
  @spec open(atom(), keyword()) :: :ok | {:error, Comn.Errors.ErrorStruct.t()}
  def open(name, opts) when is_atom(name) and is_list(opts) do
    start(name, opts, &GenServer.start/3) |> started()
  end

  @doc "Supervisor entry point: `start_link(name: :audit, conn: :gnat)`."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    start(Keyword.fetch!(opts, :name), opts, &GenServer.start_link/3)
  end

  @doc "Stops the local process. Server-side state is kept. Idempotent."
  @spec close(atom()) :: :ok
  def close(name) when is_atom(name) do
    case Process.whereis(name) do
      nil -> :ok
      pid -> GenServer.stop(pid)
    end
  end

  @doc "Stops the local process and deletes the JetStream stream. Idempotent."
  @spec drop(atom()) :: :ok
  def drop(name) when is_atom(name) do
    case Process.whereis(name) do
      nil ->
        :ok

      pid ->
        try do
          GenServer.call(pid, :delete_server_stream)
          GenServer.stop(pid)
        catch
          :exit, _ -> :ok
        end
    end
  end

  @doc "The JetStream stream name used for a Comn stream name."
  @spec js_stream_name(atom()) :: String.t()
  def js_stream_name(name) when is_atom(name) do
    name |> Atom.to_string() |> String.replace(~r/[^A-Za-z0-9_-]/, "_")
  end

  # Comn.Repo.Stream

  @impl Comn.Repo.Stream
  def append(name, %EventStruct{} = event) when is_atom(name) do
    with {:ok, [offset]} <- call(name, {:append, [event]}), do: {:ok, offset}
  end

  def append(name, _not_event) when is_atom(name) do
    with :ok <- ensure_running(name), do: {:error, ErrReg.error!("repo.stream/invalid_event")}
  end

  @impl Comn.Repo.Stream
  def append_many(name, events) when is_atom(name) and is_list(events) do
    with :ok <- ensure_running(name),
         :ok <- validate_events(events) do
      call(name, {:append, events})
    end
  end

  @impl Comn.Repo.Stream
  def read(name, cursor, count) when is_atom(name) and is_integer(count) and count > 0 do
    call(name, {:read, cursor, count})
  end

  @impl Comn.Repo.Stream
  def head(name) when is_atom(name), do: call(name, :head)

  @impl Comn.Repo.Stream
  def tail(name) when is_atom(name), do: call(name, :tail)

  @impl Comn.Repo.Stream
  def subscribe(name, _opts) when is_atom(name) do
    with :ok <- ensure_running(name),
         ref = make_ref(),
         {:ok, _owner} <- Registry.register(@registry, {:stream, name}, ref),
         :ok <- GenServer.call(name, :ensure_consumer) do
      {:ok, ref}
    end
  end

  @impl Comn.Repo.Stream
  def unsubscribe(name, ref) when is_atom(name) and is_reference(ref) do
    Registry.unregister_match(@registry, {:stream, name}, ref)
  end

  @impl Comn.Repo.Stream
  def commit(name, group, offset) when is_atom(name), do: call(name, {:commit, group, offset})

  @impl Comn.Repo.Stream
  def position(name, group) when is_atom(name), do: call(name, {:position, group})

  # Comn.Repo

  @impl Comn.Repo
  def describe(name) when is_atom(name), do: call(name, :describe)

  @impl Comn.Repo
  def get(name, opts) when is_atom(name) and is_list(opts) do
    call(name, {:get, Keyword.get(opts, :offset)})
  end

  @impl Comn.Repo
  def set(name, opts) when is_atom(name) and is_list(opts) do
    case Keyword.fetch(opts, :event) do
      {:ok, event} -> append(name, event)
      :error -> {:error, ErrReg.error!("repo.stream/invalid_event")}
    end
  end

  @impl Comn.Repo
  def delete(_name, _opts), do: {:error, ErrReg.error!("repo.stream/append_only")}

  @impl Comn.Repo
  def observe(name, _opts) when is_atom(name) do
    Stream.resource(
      fn -> :head end,
      fn
        :done ->
          {:halt, nil}

        cursor ->
          case read(name, cursor, 100) do
            {:ok, []} -> {:halt, nil}
            {:ok, batch} -> {batch, elem(List.last(batch), 0) + 1}
            {:error, _} -> {:halt, nil}
          end
      end,
      fn _ -> :ok end
    )
  end

  # Comn

  @impl Comn
  def look, do: "Stream.JetStream — NATS JetStream-backed durable append-only stream"

  @impl Comn
  def recon do
    %{type: :implementation, implements: Comn.Repo.Stream, backend: :jetstream, durable?: true}
  end

  @impl Comn
  def choices do
    %{
      actions: [
        :open,
        :close,
        :drop,
        :append,
        :read,
        :head,
        :tail,
        :subscribe,
        :unsubscribe,
        :commit,
        :position
      ],
      cursors: [:head, :tail, :offset],
      opts: [conn: "Gnat connection name or pid"]
    }
  end

  @impl Comn
  def act(%{action: :open, name: n, conn: c}), do: {:ok, open(n, conn: c)}
  def act(%{action: :close, name: n}), do: {:ok, close(n)}
  def act(%{action: :drop, name: n}), do: {:ok, drop(n)}
  def act(%{action: :append, name: n, event: e}), do: append(n, e)
  def act(%{action: :read, name: n, from: f, count: c}), do: read(n, f, c)
  def act(%{action: :head, name: n}), do: head(n)
  def act(%{action: :tail, name: n}), do: tail(n)
  def act(%{action: :subscribe, name: n}), do: subscribe(n, [])
  def act(%{action: :unsubscribe, name: n, ref: r}), do: {:ok, unsubscribe(n, r)}
  def act(%{action: :commit, name: n, group: g, offset: o}), do: commit(n, g, o)
  def act(%{action: :position, name: n, group: g}), do: position(n, g)
  def act(input), do: Comn.unknown_action(input)

  # GenServer

  @impl GenServer
  def init({name, conn}) do
    js = js_stream_name(name)
    subject = "comn.stream.#{js}"

    with {:ok, _} <- JS.create(conn, %JS{name: js, subjects: [subject]}),
         {:ok, _} <- KV.create_bucket(conn, @bucket) do
      {:ok, %{name: name, conn: conn, js: js, subject: subject, consumer: nil}}
    else
      {:error, reason} -> {:stop, {:backend_error, reason}}
    end
  end

  @impl GenServer
  def terminate(_reason, %{conn: conn, consumer: %{sid: sid}}), do: Gnat.unsub(conn, sid)
  def terminate(_reason, _state), do: :ok

  @impl GenServer
  def handle_call({:append, events}, _from, %{conn: conn, subject: subject} = s) do
    reply =
      Enum.reduce_while(events, {:ok, []}, fn event, {:ok, acc} ->
        case Gnat.request(conn, subject, :erlang.term_to_binary(event)) do
          {:ok, %{body: body}} -> {:cont, {:ok, [Jason.decode!(body)["seq"] | acc]}}
          {:error, reason} -> {:halt, {:error, backend_error(reason)}}
        end
      end)

    case reply do
      {:ok, offsets} -> {:reply, {:ok, Enum.reverse(offsets)}, s}
      error -> {:reply, error, s}
    end
  end

  def handle_call({:read, cursor, n}, _from, s) do
    reply =
      with {:ok, %{first: first, last: last}} <- range(s) do
        case cursor do
          _ when first == nil -> {:ok, []}
          :head -> {:ok, fetch_from(s, first, last, n)}
          :tail -> {:ok, fetch_from(s, max(first, last - n + 1), last, n)}
          offset when is_integer(offset) -> {:ok, fetch_from(s, offset, last, n)}
          bad -> {:error, ErrReg.error!("repo.stream/invalid_offset", field: inspect(bad))}
        end
      end

    {:reply, reply, s}
  end

  def handle_call(:head, _from, s) do
    {:reply, with({:ok, %{last: last}} <- range(s), do: {:ok, last}), s}
  end

  def handle_call(:tail, _from, s) do
    {:reply, with({:ok, %{first: first}} <- range(s), do: {:ok, first}), s}
  end

  def handle_call(:describe, _from, %{name: name} = s) do
    reply =
      with {:ok, %{first: first, last: last, count: count}} <- range(s) do
        {:ok, %{name: name, head: last, tail: first, count: count}}
      end

    {:reply, reply, s}
  end

  def handle_call({:get, offset}, _from, s) do
    reply =
      case fetch_one(s, offset) do
        {:ok, {_o, event}} -> {:ok, event}
        :missing -> {:error, ErrReg.error!("repo.stream/invalid_offset", field: inspect(offset))}
      end

    {:reply, reply, s}
  end

  def handle_call({:commit, group, offset}, _from, %{conn: conn} = s) do
    reply =
      with {:ok, %{first: first, last: last}} <- range(s) do
        if is_integer(offset) and first != nil and offset >= first and offset <= last do
          case KV.put_value(conn, @bucket, group_key(s, group), Integer.to_string(offset)) do
            :ok -> :ok
            {:error, reason} -> {:error, backend_error(reason)}
          end
        else
          {:error, ErrReg.error!("repo.stream/invalid_offset", field: inspect(offset))}
        end
      end

    {:reply, reply, s}
  end

  def handle_call({:position, group}, _from, %{conn: conn} = s) do
    reply =
      case KV.get_value(conn, @bucket, group_key(s, group)) do
        value when is_binary(value) -> {:ok, String.to_integer(value)}
        # ponytail: a missing key and a server error both land here as nil
        _ -> {:ok, nil}
      end

    {:reply, reply, s}
  end

  def handle_call(:ensure_consumer, _from, %{consumer: %{}} = s), do: {:reply, :ok, s}

  def handle_call(:ensure_consumer, _from, %{conn: conn, js: js} = s) do
    inbox = "_INBOX.comn.stream." <> js

    consumer = %Consumer{
      stream_name: js,
      deliver_subject: inbox,
      deliver_policy: :new,
      ack_policy: :none,
      # gnat defaults this to 20_000, which the server rejects with ack_policy :none
      max_ack_pending: 0
    }

    with {:ok, _} <- Consumer.create(conn, consumer),
         {:ok, sid} <- Gnat.sub(conn, self(), inbox) do
      {:reply, :ok, %{s | consumer: %{sid: sid, inbox: inbox}}}
    else
      {:error, reason} -> {:reply, {:error, backend_error(reason)}, s}
    end
  end

  def handle_call(:delete_server_stream, _from, %{conn: conn, js: js} = s) do
    # ponytail: group keys for this stream are left in the KV bucket
    _ = JS.delete(conn, js)
    {:reply, :ok, s}
  end

  @impl GenServer
  def handle_info({:msg, %{body: body} = msg}, %{name: name} = s) do
    case Message.metadata(msg) do
      {:ok, %{stream_seq: seq}} ->
        event = :erlang.binary_to_term(body, [:safe])

        Registry.dispatch(@registry, {:stream, name}, fn entries ->
          for {pid, _ref} <- entries, do: send(pid, {:stream, name, seq, event})
        end)

      _ ->
        :ok
    end

    {:noreply, s}
  end

  def handle_info(_other, s), do: {:noreply, s}

  # Internals

  defp start(name, opts, starter) do
    case Keyword.fetch(opts, :conn) do
      {:ok, conn} when is_atom(conn) or is_pid(conn) ->
        starter.(__MODULE__, {name, conn}, name: name)

      _ ->
        {:error,
         ErrReg.error!("repo.stream/invalid_opts",
           field: "conn",
           suggestion: "pass conn: :my_gnat"
         )}
    end
  end

  defp started({:ok, _pid}), do: :ok

  defp started({:error, {:already_started, _}}),
    do: {:error, ErrReg.error!("repo.stream/already_exists")}

  defp started({:error, {:backend_error, reason}}), do: {:error, backend_error(reason)}
  defp started({:error, %Comn.Errors.ErrorStruct{} = err}), do: {:error, err}

  defp call(name, msg) do
    with :ok <- ensure_running(name), do: GenServer.call(name, msg, 15_000)
  end

  defp ensure_running(name) do
    case Process.whereis(name) do
      nil -> {:error, ErrReg.error!("repo.stream/not_found", field: name)}
      _ -> :ok
    end
  end

  defp validate_events(events) do
    if Enum.all?(events, &match?(%EventStruct{}, &1)),
      do: :ok,
      else: {:error, ErrReg.error!("repo.stream/invalid_event")}
  end

  defp backend_error(reason) do
    ErrReg.error!("repo.stream/backend_error", message: "JetStream: #{inspect(reason)}")
  end

  # {first, last} sequences, nil when the stream holds no messages
  defp range(%{conn: conn, js: js}) do
    case JS.info(conn, js) do
      {:ok, %{state: %{messages: 0}}} -> {:ok, %{first: nil, last: nil, count: 0}}
      {:ok, %{state: st}} -> {:ok, %{first: st.first_seq, last: st.last_seq, count: st.messages}}
      {:error, reason} -> {:error, backend_error(reason)}
    end
  end

  # ponytail: one request per message; swap for a pull-consumer batch if read throughput matters
  defp fetch_from(_s, _seq, nil, _n), do: []

  defp fetch_from(s, seq, last, n) do
    Stream.iterate(seq, &(&1 + 1))
    |> Stream.take_while(&(&1 <= last))
    |> Stream.map(&fetch_one(s, &1))
    |> Stream.reject(&(&1 == :missing))
    |> Stream.map(fn {:ok, pair} -> pair end)
    |> Enum.take(n)
  end

  defp fetch_one(%{conn: conn, js: js}, seq) when is_integer(seq) and seq > 0 do
    case JS.get_message(conn, js, %{seq: seq}) do
      {:ok, %{data: data}} -> {:ok, {seq, :erlang.binary_to_term(data, [:safe])}}
      {:error, _} -> :missing
    end
  end

  defp fetch_one(_s, _seq), do: :missing

  defp group_key(%{js: js}, group) do
    js <> "." <> Base.url_encode64(:erlang.term_to_binary(group), padding: false)
  end
end
