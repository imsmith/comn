defmodule Comn.Presence do
  @moduledoc """
  Zone-scoped presence: who is where, doing what.

  Defines a behaviour for spatial presence backends (`announce/3`, `who/1`)
  and provides a default Agent-backed local implementation under the same
  module. External adapters (e.g. a distributed NATS-backed presence) can
  implement `Comn.Presence` as a behaviour and be selected at the call site.

  Presence states are open-ended atoms. Conventional values are `:here`,
  `:busy`, and `:gone`. Announcing `:gone` removes the actor from the zone.

  ## Examples

      iex> zone = Comn.Zone.new(realm: :local, locale: "lobby-doc")
      iex> :ok = Comn.Presence.announce(zone, "alice", :here)
      iex> {:ok, actors} = Comn.Presence.who(zone)
      iex> {"alice", :here} in actors
      true
  """

  @behaviour Comn

  alias Comn.Errors.ErrorStruct
  alias Comn.Zone

  @type actor_id :: String.t()
  @type state :: atom()

  @doc "Records that `actor` is in `zone` with the given `state`. `:gone` removes."
  @callback announce(Zone.t(), actor_id(), state()) :: :ok | {:error, ErrorStruct.t()}

  @doc "Returns `{:ok, [{actor_id, state}, ...]}` for actors currently in `zone`."
  @callback who(Zone.t()) :: {:ok, [{actor_id(), state()}]} | {:error, ErrorStruct.t()}

  @agent __MODULE__.Agent

  @doc false
  def child_spec(_opts) do
    %{
      id: @agent,
      start: {Agent, :start_link, [fn -> %{} end, [name: @agent]]}
    }
  end

  @doc "Announces an actor's presence in a zone. `:gone` removes the actor."
  @spec announce(Zone.t(), actor_id(), state()) :: :ok
  def announce(%Zone{} = zone, actor, :gone) do
    key = Zone.to_string(zone)
    Agent.update(@agent, fn store ->
      case Map.fetch(store, key) do
        {:ok, actors} ->
          remaining = Map.delete(actors, actor)
          if remaining == %{}, do: Map.delete(store, key), else: Map.put(store, key, remaining)

        :error ->
          store
      end
    end)
  end

  def announce(%Zone{} = zone, actor, state) when is_atom(state) do
    key = Zone.to_string(zone)
    Agent.update(@agent, fn store ->
      Map.update(store, key, %{actor => state}, &Map.put(&1, actor, state))
    end)
  end

  @doc "Lists `{actor, state}` pairs in a zone."
  @spec who(Zone.t()) :: {:ok, [{actor_id(), state()}]}
  def who(%Zone{} = zone) do
    key = Zone.to_string(zone)
    actors =
      @agent
      |> Agent.get(&Map.get(&1, key, %{}))
      |> Map.to_list()
    {:ok, actors}
  end

  # Comn behaviour

  @impl Comn
  def look, do: "Presence — zone-scoped actor presence (announce, who)"

  @impl Comn
  def recon do
    %{
      type: :facade,
      callbacks: [:announce, :who],
      states: [:here, :busy, :gone],
      backend: :agent
    }
  end

  @impl Comn
  def choices do
    %{states: [:here, :busy, :gone], actions: [:announce, :who]}
  end

  @impl Comn
  def act(%{action: :announce, zone: z, actor: a, state: s}), do: {:ok, announce(z, a, s)}
  def act(%{action: :who, zone: z}), do: who(z)
  def act(_), do: {:error, :unknown_action}
end
