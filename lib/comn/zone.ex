defmodule Comn.Zone do
  @moduledoc """
  Structured spatial locator: `realm.region.locale`.

  A zone identifies *where* something lives — the realm (network topology
  bucket: `:local`, `:mesh`, `:cluster`, `:region`, `:global`), an optional
  region within that realm (e.g. `"us-east"`, `"home"`), and an optional
  locale within that region (e.g. `"kitchen"`, `"room_a"`).

  Zones are used as ambient context (see `Comn.Contexts`) and as spatial
  addresses for repo operations (see `Comn.Repo` spatial callbacks
  `enter/2`, `exit/2`, `discover/2`).

  ## String form

  A zone serializes to a dot-delimited string and round-trips through
  `parse/1`:

      iex> Comn.Zone.to_string(Comn.Zone.new(realm: :mesh, region: "home", locale: "kitchen"))
      "mesh.home.kitchen"

      iex> Comn.Zone.to_string(Comn.Zone.local())
      "local"

      iex> {:ok, zone} = Comn.Zone.parse("cluster.us-east")
      iex> {zone.realm, zone.region, zone.locale}
      {:cluster, "us-east", nil}
  """

  @behaviour Comn

  @realms [:local, :mesh, :cluster, :region, :global]

  # All fields default; constructing with no args yields the local zone.
  @enforce_keys []
  defstruct realm: :local, region: nil, locale: nil

  @type realm :: :local | :mesh | :cluster | :region | :global
  @type t :: %__MODULE__{
          realm: realm(),
          region: String.t() | nil,
          locale: String.t() | nil
        }

  @doc """
  The default local zone.

  ## Examples

      iex> Comn.Zone.local()
      %Comn.Zone{realm: :local, region: nil, locale: nil}
  """
  @spec local() :: t()
  def local, do: %__MODULE__{realm: :local}

  @doc """
  Constructs a zone from a keyword list or map of fields.

  Unknown fields raise; use `parse/1` for untrusted string input.

  ## Examples

      iex> Comn.Zone.new(realm: :mesh, region: "home", locale: "kitchen")
      %Comn.Zone{realm: :mesh, region: "home", locale: "kitchen"}

      iex> Comn.Zone.new(%{realm: :global})
      %Comn.Zone{realm: :global, region: nil, locale: nil}
  """
  @spec new(keyword() | map()) :: t()
  def new(fields) when is_list(fields), do: struct!(__MODULE__, fields)
  def new(fields) when is_map(fields), do: struct!(__MODULE__, Map.to_list(fields))

  @doc """
  Parses a dot-delimited zone string `"realm[.region[.locale]]"`.

  The realm must be one of `#{inspect(@realms)}`; region and locale stay
  as strings. Returns `{:error, :empty}` on empty input or
  `{:error, {:unknown_realm, str}}` on unknown realms.

  ## Examples

      iex> {:ok, zone} = Comn.Zone.parse("mesh.home.kitchen")
      iex> {zone.realm, zone.region, zone.locale}
      {:mesh, "home", "kitchen"}

      iex> {:ok, zone} = Comn.Zone.parse("local")
      iex> zone.realm
      :local

      iex> Comn.Zone.parse("")
      {:error, :empty}

      iex> Comn.Zone.parse("nowhere.foo")
      {:error, {:unknown_realm, "nowhere"}}
  """
  @spec parse(String.t()) :: {:ok, t()} | {:error, term()}
  def parse(""), do: {:error, :empty}

  def parse(str) when is_binary(str) do
    case String.split(str, ".", parts: 3) do
      [realm] -> build(realm, nil, nil)
      [realm, region] -> build(realm, region, nil)
      [realm, region, locale] -> build(realm, region, locale)
    end
  end

  defp build(realm_str, region, locale) do
    case realm_atom(realm_str) do
      {:ok, realm} -> {:ok, %__MODULE__{realm: realm, region: region, locale: locale}}
      :error -> {:error, {:unknown_realm, realm_str}}
    end
  end

  defp realm_atom(str) do
    Enum.find_value(@realms, :error, fn r ->
      if Atom.to_string(r) == str, do: {:ok, r}
    end)
  end

  @doc """
  Serializes a zone to its dot-delimited string form.

  Nil region and locale are dropped, so a zone with only a realm renders
  as just the realm name. Round-trips with `parse/1`.

  ## Examples

      iex> Comn.Zone.to_string(Comn.Zone.new(realm: :mesh, region: "home"))
      "mesh.home"

      iex> Comn.Zone.to_string(Comn.Zone.local())
      "local"
  """
  @spec to_string(t()) :: String.t()
  def to_string(%__MODULE__{realm: realm, region: region, locale: locale}) do
    [Atom.to_string(realm), region, locale]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(".")
  end

  # Comn behaviour

  @impl Comn
  def look, do: "Zone — structured spatial locator (realm.region.locale)"

  @impl Comn
  def recon do
    %{
      type: :facade,
      struct: __MODULE__,
      fields: [:realm, :region, :locale],
      realms: @realms
    }
  end

  @impl Comn
  def choices do
    %{realms: @realms, actions: [:parse, :to_string, :new, :local]}
  end

  @impl Comn
  def act(%{action: :parse, input: str}), do: parse(str)
  def act(%{action: :to_string, zone: %__MODULE__{} = z}), do: {:ok, __MODULE__.to_string(z)}
  def act(%{action: :new, fields: f}), do: {:ok, new(f)}
  def act(%{action: :local}), do: {:ok, local()}
  def act(_), do: {:error, :unknown_action}
end
