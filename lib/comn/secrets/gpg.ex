defmodule Comn.Secrets.GPG do
  @moduledoc """
  OpenPGP backend for `Comn.Secrets` that drives the system `gpg` binary.

  Recipient mode encrypts to one or more public keys in a GnuPG keyring;
  symmetric mode encrypts with a passphrase. Either can be signed. The
  output is a complete OpenPGP message, armored by default, that the stock
  `gpg` CLI can decrypt.

  ## Keys

  Recipient key: `public` is the raw 20- or 32-byte primary fingerprint,
  `private` is nil. Symmetric key: `metadata.mode` is `:symmetric`,
  `public` is a label, `private` is the passphrase.

  ## Configuration

  Passed via `%Comn.Secrets.Key{metadata: ...}`:

  - `mode` — `:symmetric` for passphrase encryption; absent means recipient
  - `homedir` — GnuPG home directory; omitted means gpg's default
  - `recipients` — extra recipient fingerprints as hex strings
  - `sign` — `true` (sign with `public`) or a signer fingerprint as hex
  - `armor` — `false` for binary output; default `true`
  - `gpg_path` — absolute path to the gpg binary; default `gpg` on PATH,
    `secrets/gpg_unavailable` when there is none
  - `timeout_ms` — per-invocation timeout; default 30 000, then
    `secrets/gpg_error`

  ## Signing policy

  On lock, `sign: true` signs with `public` (recipient mode only; in
  symmetric mode it is `secrets/invalid_gpg_config`) and a hex `sign` signs
  with that key. On unlock a signature is required when the key sets `sign`
  or the blob says `signed: true`: gpg's `VALIDSIG` primary fingerprint must
  equal the expected signer, else `secrets/authentication_failed`. Any
  `BADSIG`, `ERRSIG`, or `NO_PUBKEY` fails regardless.

  ## Process boundary

  Plaintext, ciphertext, and passphrase travel over the child's stdin;
  only their byte count appears on argv. gpg's machine status goes to a
  file in a private temporary directory that is removed after every call.
  Status keywords are the only gpg output that ever reaches an error.

  ## Examples

      iex> Comn.Secrets.GPG.look()
      "Secrets.GPG — OpenPGP via the system gpg binary, keys stay in the GnuPG keyring"

      iex> %{key_management: :keyring} = Comn.Secrets.GPG.recon()
  """

  @behaviour Comn
  @behaviour Comn.Secrets

  alias Comn.Errors.Registry, as: ErrReg
  alias Comn.Events.EventStruct
  alias Comn.Secrets.{Key, LockedBlob, Utils}

  @armor_header "-----BEGIN PGP MESSAGE-----"
  @default_timeout 30_000
  @loopback ["--pinentry-mode", "loopback", "--passphrase-fd", "0"]
  @shell ~S(n=$1; shift; head -c "$n" | exec "$@" 2>/dev/null)

  @impl true
  def lock(blob, %Key{algorithm: :gpg} = key) when is_binary(blob) do
    with :ok <- Utils.validate_key(key),
         {:ok, args, stdin, meta} <- lock_plan(key, blob),
         {:ok, sign, signer} <- sign_args(key),
         {:ok, encrypted, _status} <- run(key, common_args(key) ++ args ++ sign, stdin) do
      {:ok,
       %LockedBlob{
         cipher: :gpg,
         encrypted: encrypted,
         key_hint: Key.fingerprint(key),
         metadata:
           Map.merge(meta, %{
             created_at: DateTime.to_iso8601(DateTime.utc_now()),
             algorithm: :gpg,
             armor: armor?(key),
             signed: signer != nil
           })
       }}
    end
  end

  def lock(_blob, _key), do: {:error, ErrReg.error!("secrets/invalid_key")}

  @impl true
  def unlock(%LockedBlob{cipher: :gpg} = locked, %Key{algorithm: :gpg} = key) do
    with :ok <- Utils.validate_key(key),
         true <- hint_ok?(locked, key),
         {args, stdin} = unlock_plan(key, locked),
         {:ok, plaintext, status} <- run(key, common_args(key) ++ args, stdin),
         :ok <- verify_signature(status, key, locked) do
      {:ok, plaintext}
    else
      false -> {:error, ErrReg.error!("secrets/wrong_key")}
      {:error, _} = err -> err
    end
  end

  def unlock(%LockedBlob{cipher: :gpg}, _key), do: {:error, ErrReg.error!("secrets/invalid_key")}
  def unlock(%LockedBlob{}, _key), do: {:error, ErrReg.error!("secrets/invalid_ciphertext")}
  def unlock(_locked, _key), do: {:error, ErrReg.error!("secrets/invalid_key")}

  @impl true
  def wrap(blobs, key), do: Utils.wrap(__MODULE__, blobs, key)

  @doc """
  Puts a locked blob into any `Comn.Repo` shape.

  `as: :raw` writes the bare OpenPGP message with `set(handle, value: ...)`
  so the stock `gpg` CLI can read the file; only `Comn.Repo.File` supports
  it. Otherwise the blob travels as the `data` of a `:secrets_locked` event
  on topic `"comn.secrets"` and the minted event id is returned with the
  shape's own `set` result.

  Errors: `secrets/invalid_gpg_config` for `as: :raw` on a non-File shape,
  plus whatever the shape's `set` returns.
  """
  @spec put(LockedBlob.t(), module(), Comn.Repo.Handle.t(), keyword()) ::
          {:ok, Comn.Repo.Handle.t()}
          | {:ok, String.t(), term()}
          | {:error, Comn.Errors.ErrorStruct.t()}
  def put(%LockedBlob{cipher: :gpg} = locked, repo, handle, opts) when is_list(opts) do
    case Keyword.get(opts, :as) do
      :raw when repo == Comn.Repo.File -> repo.set(handle, value: locked.encrypted)
      :raw -> {:error, ErrReg.error!("secrets/invalid_gpg_config", field: "as")}
      _ -> put_event(locked, repo, handle)
    end
  end

  defp put_event(locked, repo, handle) do
    e = EventStruct.new(:secrets_locked, "comn.secrets", locked, __MODULE__)

    case repo.set(handle, event: e) do
      :ok -> {:ok, e.id, :ok}
      {:ok, _} = result -> {:ok, e.id, result}
      {:error, _} = err -> err
    end
  end

  @doc """
  Fetches a locked blob back from a `Comn.Repo` shape.

  `as: :raw` reads a loaded `Comn.Repo.File` and rebuilds the blob from the
  bytes (`key_hint` nil, `armor` detected from the armor header). `id: id`
  gets the event by id and returns its `data`.

  Errors: `secrets/invalid_gpg_config` without either option or for `as:
  :raw` on a non-File shape, `secrets/invalid_container` when the event's
  data is not a gpg blob, plus whatever the shape's `get`/`read` returns.
  """
  @spec fetch(module(), Comn.Repo.Handle.t(), keyword()) ::
          {:ok, LockedBlob.t()} | {:error, Comn.Errors.ErrorStruct.t()}
  def fetch(repo, handle, opts) when is_list(opts) do
    case {Keyword.get(opts, :as), Keyword.get(opts, :id)} do
      {:raw, _} when repo == Comn.Repo.File -> fetch_raw(handle)
      {:raw, _} -> {:error, ErrReg.error!("secrets/invalid_gpg_config", field: "as")}
      {_, nil} -> {:error, ErrReg.error!("secrets/invalid_gpg_config", field: "id")}
      {_, id} -> fetch_event(repo, handle, id)
    end
  end

  defp fetch_raw(handle) do
    with {:ok, bytes} when is_binary(bytes) <- Comn.Repo.File.read(handle) do
      {:ok,
       %LockedBlob{
         cipher: :gpg,
         encrypted: bytes,
         metadata: %{armor: String.starts_with?(bytes, @armor_header), mode: nil, signed: nil}
       }}
    end
  end

  defp fetch_event(repo, handle, id) do
    case repo.get(handle, id: id) do
      {:ok, %EventStruct{data: %LockedBlob{cipher: :gpg} = locked}} -> {:ok, locked}
      {:ok, _} -> {:error, ErrReg.error!("secrets/invalid_container")}
      {:error, _} = err -> err
    end
  end

  @impl true
  def unwrap(locked, key), do: Utils.unwrap(__MODULE__, locked, key)

  # Argument building

  defp symmetric?(%Key{metadata: meta}), do: meta[:mode] == :symmetric

  defp lock_plan(%Key{private: pw} = key, blob) do
    if symmetric?(key) do
      with {:ok, args} <- symmetric_args(key) do
        {:ok, args, pw <> "\n" <> blob, %{mode: :symmetric}}
      end
    else
      with {:ok, args, recipients} <- recipient_args(key) do
        {:ok, args, blob, %{mode: :recipient, recipients: recipients}}
      end
    end
  end

  defp unlock_plan(%Key{private: pw} = key, %LockedBlob{encrypted: data}) do
    if symmetric?(key),
      do: {@loopback ++ ["--decrypt"], pw <> "\n" <> data},
      else: {["--decrypt"], data}
  end

  defp symmetric_args(key), do: {:ok, @loopback ++ armor_args(key) ++ ["--symmetric"]}

  # Signing

  defp sign_args(%Key{metadata: meta} = key) do
    case signer_hex(meta[:sign], key) do
      {:ok, nil} -> {:ok, [], nil}
      {:ok, hex} -> {:ok, ["--sign", "--local-user", hex], hex}
      {:error, _} = err -> err
    end
  end

  defp signer_hex(sign, _key) when sign in [nil, false], do: {:ok, nil}

  defp signer_hex(sign, key) when is_binary(sign) and is_binary(key.public),
    do: Utils.gpg_fingerprint_hex(sign)

  defp signer_hex(true, %Key{public: pub} = key) do
    if symmetric?(key),
      do: {:error, ErrReg.error!("secrets/invalid_gpg_config", field: "sign")},
      else: {:ok, Base.encode16(pub)}
  end

  defp signer_hex(_, _key),
    do: {:error, ErrReg.error!("secrets/invalid_gpg_config", field: "sign")}

  defp verify_signature(status, %Key{metadata: meta} = key, %LockedBlob{metadata: locked_meta}) do
    required? = meta[:sign] not in [nil, false] or locked_meta[:signed] == true
    bad? = Enum.any?(status, &String.starts_with?(&1, ["BADSIG ", "ERRSIG ", "NO_PUBKEY "]))

    cond do
      bad? -> {:error, ErrReg.error!("secrets/authentication_failed", field: "signature")}
      not required? -> :ok
      true -> check_validsig(status, signer_hex(meta[:sign], key))
    end
  end

  defp check_validsig(status, {:ok, expected}) do
    signers =
      for "VALIDSIG " <> fields <- status, do: fields |> String.split(" ") |> List.last()

    if signers != [] and (expected == nil or expected in signers),
      do: :ok,
      else: {:error, ErrReg.error!("secrets/authentication_failed", field: "signature")}
  end

  defp check_validsig(_status, {:error, _} = err), do: err

  defp common_args(%Key{metadata: meta}) do
    base = ["--batch", "--yes", "--quiet", "--no-tty"]
    if meta[:homedir], do: base ++ ["--homedir", meta.homedir], else: base
  end

  defp armor?(%Key{metadata: meta}), do: meta[:armor] != false

  defp armor_args(key), do: if(armor?(key), do: ["--armor"], else: [])

  defp recipient_args(%Key{public: fpr, metadata: meta} = key) do
    with {:ok, extra} <- fingerprints(meta[:recipients] || []) do
      recipients = [Base.encode16(fpr) | extra]
      flags = Enum.flat_map(recipients, &["--recipient", &1])
      {:ok, ["--trust-model", "always"] ++ armor_args(key) ++ ["--encrypt"] ++ flags, recipients}
    end
  end

  defp fingerprints(list) when is_list(list) do
    Enum.reduce_while(list, {:ok, []}, fn hex, {:ok, acc} ->
      case Utils.gpg_fingerprint_hex(hex) do
        {:ok, norm} -> {:cont, {:ok, acc ++ [norm]}}
        err -> {:halt, err}
      end
    end)
  end

  defp fingerprints(_), do: {:error, ErrReg.error!("secrets/invalid_gpg_config")}

  defp hint_ok?(%LockedBlob{key_hint: nil}, _key), do: true

  defp hint_ok?(%LockedBlob{key_hint: hint, metadata: meta}, %Key{public: pub} = key) do
    Key.fingerprint_matches?(hint, key) or Base.encode16(pub) in List.wrap(meta[:recipients])
  end

  # Process boundary

  defp run(%Key{metadata: meta}, args, stdin) do
    with {:ok, gpg} <- binary(meta[:gpg_path]),
         :ok <- check_homedir(meta[:homedir]) do
      dir = Path.join(System.tmp_dir!(), "comn_gpg_status_#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      File.chmod!(dir, 0o700)
      status_file = Path.join(dir, "status")

      try do
        argv =
          [@shell, "sh", Integer.to_string(byte_size(stdin)), gpg | args] ++
            ["--status-file", status_file]

        port =
          Port.open({:spawn_executable, "/bin/sh"}, [
            :binary,
            :exit_status,
            :use_stdio,
            :hide,
            args: ["-c" | argv]
          ])

        Port.command(port, stdin)
        timeout = meta[:timeout_ms] || @default_timeout

        case collect(port, [], timeout) do
          {:ok, 0, out} ->
            {:ok, out, status_lines(status_file)}

          {:ok, _code, _out} ->
            {:error, status_error(status_lines(status_file))}

          :timeout ->
            {:error,
             ErrReg.error!("secrets/gpg_error", message: "gpg timed out after #{timeout} ms")}
        end
      after
        File.rm_rf!(dir)
      end
    end
  end

  defp collect(port, acc, timeout) do
    receive do
      {^port, {:data, chunk}} -> collect(port, [acc | chunk], timeout)
      {^port, {:exit_status, code}} -> {:ok, code, IO.iodata_to_binary(acc)}
    after
      timeout ->
        Port.close(port)
        :timeout
    end
  end

  defp binary(nil) do
    case System.find_executable("gpg") do
      nil -> {:error, ErrReg.error!("secrets/gpg_unavailable")}
      path -> {:ok, path}
    end
  end

  defp binary(path) when is_binary(path) do
    if Path.type(path) == :absolute and File.regular?(path),
      do: {:ok, path},
      else: {:error, ErrReg.error!("secrets/invalid_gpg_config", field: "gpg_path")}
  end

  defp binary(_), do: {:error, ErrReg.error!("secrets/invalid_gpg_config", field: "gpg_path")}

  defp check_homedir(nil), do: :ok

  defp check_homedir(dir) when is_binary(dir) do
    if File.dir?(dir),
      do: :ok,
      else: {:error, ErrReg.error!("secrets/invalid_gpg_config", field: "homedir")}
  end

  defp check_homedir(_),
    do: {:error, ErrReg.error!("secrets/invalid_gpg_config", field: "homedir")}

  defp status_lines(file) do
    case File.read(file) do
      {:ok, text} ->
        for "[GNUPG:] " <> rest <- String.split(text, "\n"), do: rest

      _ ->
        []
    end
  end

  @status_codes [
    {"DECRYPTION_FAILED", "secrets/wrong_key"},
    {"NO_SECKEY", "secrets/wrong_key"},
    {"BAD_PASSPHRASE", "secrets/wrong_key"},
    {"MISSING_PASSPHRASE", "secrets/wrong_key"},
    {"BADSIG", "secrets/authentication_failed"},
    {"ERRSIG", "secrets/authentication_failed"},
    {"NO_PUBKEY", "secrets/authentication_failed"},
    {"NODATA", "secrets/invalid_ciphertext"},
    {"UNEXPECTED", "secrets/invalid_ciphertext"},
    {"INV_RECP", "secrets/invalid_gpg_config"},
    {"KEYEXPIRED", "secrets/invalid_gpg_config"},
    {"KEYREVOKED", "secrets/invalid_gpg_config"}
  ]

  defp status_error(lines) do
    keywords = Enum.map(lines, &(&1 |> String.split(" ", parts: 2) |> hd()))

    case Enum.find(@status_codes, fn {kw, _} -> kw in keywords end) do
      {kw, code} -> ErrReg.error!(code, field: kw)
      nil -> ErrReg.error!("secrets/gpg_error")
    end
  end

  # Comn introspection

  @impl Comn
  def look,
    do: "Secrets.GPG — OpenPGP via the system gpg binary, keys stay in the GnuPG keyring"

  @impl Comn
  def recon do
    %{
      backend: :gpg,
      requires: [:gpg_binary],
      key_management: :keyring,
      modes: [:recipient, :symmetric],
      signing: true,
      type: :implementation
    }
  end

  @impl Comn
  def choices do
    %{
      operations: ["lock", "unlock", "wrap", "unwrap", "put", "fetch"],
      config: ["mode", "homedir", "recipients", "sign", "armor", "gpg_path", "timeout_ms"]
    }
  end

  @impl Comn
  def act(%{action: :lock, blob: blob, key: key}), do: lock(blob, key)
  def act(%{action: :unlock, locked: locked, key: key}), do: unlock(locked, key)
  def act(%{action: :wrap, blobs: blobs, key: key}), do: wrap(blobs, key)
  def act(%{action: :unwrap, locked: locked, key: key}), do: unwrap(locked, key)

  def act(%{action: :put, locked: locked, repo: repo, handle: handle, opts: opts}),
    do: put(locked, repo, handle, opts)

  def act(%{action: :fetch, repo: repo, handle: handle, opts: opts}),
    do: fetch(repo, handle, opts)

  def act(input), do: Comn.unknown_action(input)
end
