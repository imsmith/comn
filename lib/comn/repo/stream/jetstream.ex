defmodule Comn.Repo.Stream.JetStream do
  @moduledoc false
  # NATS JetStream stream backend. Each Comn stream maps to one JetStream
  # stream (see js_stream_name/1) on subject comn.stream.<name>; the offset
  # is JetStream's stream sequence. append publishes and waits for the
  # PubAck; read/head/tail use stream info and direct get by sequence;
  # subscribe creates one ephemeral push consumer per open stream and fans
  # deliveries out through Comn.Repo.Stream.notify/3 with the sequence
  # parsed from the $JS.ACK reply subject.
  #
  # One local unlinked GenServer per open stream, registered under the
  # stream name, holds the connection and the consumer subscription.
  # close/1 stops it (server state stays); drop/1 also deletes the server
  # stream. start_link/1 is the supervisor entry.

  @behaviour Comn.Repo.Stream.Backend

  use GenServer

  alias Comn.Errors.Registry, as: ErrReg
  alias Gnat.Jetstream.API.Consumer
  alias Gnat.Jetstream.API.Message
  alias Gnat.Jetstream.API.Stream, as: JS

  # ---- Backend ----

  @impl Comn.Repo.Stream.Backend
  def open(name, opts) when is_atom(name) do
    case start(name, opts, &GenServer.start/3) do
      {:ok, _pid} ->
        {:ok, name}

      {:error, {:already_started, _}} ->
        {:error, ErrReg.error!("repo.stream/already_exists", field: name)}

      {:error, {:backend_error, reason}} ->
        {:error, backend_error(reason)}

      {:error, %Comn.Errors.ErrorStruct{} = err} ->
        {:error, err}

      {:error, reason} ->
        {:error, backend_error(reason)}
    end
  end

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts),
    do: start(Keyword.fetch!(opts, :name), opts, &GenServer.start_link/3)

  @impl Comn.Repo.Stream.Backend
  def close(name) do
    case Process.whereis(name) do
      nil -> :ok
      pid -> GenServer.stop(pid)
    end
  end

  @impl Comn.Repo.Stream.Backend
  def drop(name) do
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

  @impl Comn.Repo.Stream.Backend
  def append(name, events), do: call(name, {:append, events})

  @impl Comn.Repo.Stream.Backend
  def read(name, cursor, count), do: call(name, {:read, cursor, count})

  @impl Comn.Repo.Stream.Backend
  def head(name), do: call(name, :head)

  @impl Comn.Repo.Stream.Backend
  def tail(name), do: call(name, :tail)

  @impl Comn.Repo.Stream.Backend
  def count(name), do: call(name, :count)

  @impl Comn.Repo.Stream.Backend
  def subscribe(name), do: call(name, :ensure_consumer)

  @doc false
  # The JetStream stream name used for a Comn stream name (tests assert the server-side mapping).
  @spec js_stream_name(atom()) :: String.t()
  def js_stream_name(name) when is_atom(name) do
    name |> Atom.to_string() |> String.replace(~r/[^A-Za-z0-9_-]/, "_")
  end

  # ---- GenServer ----

  @impl GenServer
  def init({name, conn}) do
    js = js_stream_name(name)
    subject = "comn.stream.#{js}"

    case JS.create(conn, %JS{name: js, subjects: [subject]}) do
      {:ok, _} -> {:ok, %{name: name, conn: conn, js: js, subject: subject, consumer: nil}}
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
          {:ok, %{body: body}} ->
            # live delivery comes from the push consumer (handle_info), not from here
            {:cont, {:ok, [Jason.decode!(body)["seq"] | acc]}}

          {:error, reason} ->
            {:halt, {:error, backend_error(reason)}}
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

  def handle_call(:head, _from, s),
    do: {:reply, with({:ok, %{last: last}} <- range(s), do: {:ok, last}), s}

  def handle_call(:tail, _from, s),
    do: {:reply, with({:ok, %{first: first}} <- range(s), do: {:ok, first}), s}

  def handle_call(:count, _from, s),
    do: {:reply, with({:ok, %{count: c}} <- range(s), do: {:ok, c}), s}

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
    _ = JS.delete(conn, js)
    {:reply, :ok, s}
  end

  @impl GenServer
  def handle_info({:msg, %{body: body} = msg}, %{name: name} = s) do
    case Message.metadata(msg) do
      {:ok, %{stream_seq: seq}} ->
        Comn.Repo.Stream.notify(name, seq, :erlang.binary_to_term(body, [:safe]))

      _ ->
        :ok
    end

    {:noreply, s}
  end

  def handle_info(_other, s), do: {:noreply, s}

  # ---- internals ----

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

  defp call(name, msg) do
    case Process.whereis(name) do
      nil -> {:error, ErrReg.error!("repo.stream/not_found", field: name)}
      _ -> GenServer.call(name, msg, 15_000)
    end
  end

  defp backend_error(reason) do
    ErrReg.error!("repo.stream/backend_error", message: "JetStream: #{inspect(reason)}")
  end

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
end
