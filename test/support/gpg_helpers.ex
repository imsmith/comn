defmodule Comn.Secrets.GPGHelpers do
  @moduledoc """
  Throwaway GnuPG homedirs for `Comn.Secrets.GPG` tests.

  Every homedir is private (`0700`), gets its own gpg-agent, and is torn
  down with the agent in `on_exit`.
  """

  import ExUnit.Assertions
  alias Comn.Secrets.Key

  @doc "Creates a private temporary GNUPGHOME and schedules its removal."
  @spec homedir!() :: Path.t()
  def homedir! do
    suffix = Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)
    dir = Path.join(System.tmp_dir!(), "comn_gpg_#{suffix}")
    File.mkdir_p!(dir)
    File.chmod!(dir, 0o700)

    ExUnit.Callbacks.on_exit(fn ->
      System.cmd("gpgconf", ["--homedir", dir, "--kill", "gpg-agent"], stderr_to_stdout: true)
      File.rm_rf!(dir)
    end)

    dir
  end

  @doc "Generates a passphrase-less key in `homedir` and returns its primary fingerprint."
  @spec gen_key!(Path.t(), String.t()) :: String.t()
  def gen_key!(homedir, name \\ "Comn Test <test@comn.invalid>") do
    args =
      ~w(--homedir #{homedir} --batch --pinentry-mode loopback --passphrase) ++
        ["", "--quick-gen-key", name, "default", "default", "never"]

    case System.cmd("gpg", args, stderr_to_stdout: true) do
      {_, 0} -> :ok
      {out, status} -> raise "gpg --quick-gen-key exited #{status}: #{out}"
    end

    {out, 0} =
      System.cmd("gpg", ~w(--homedir #{homedir} --with-colons --list-keys #{name}),
        stderr_to_stdout: true
      )

    out
    |> String.split("\n")
    |> Enum.find_value(fn line ->
      case String.split(line, ":") do
        ["fpr" | fields] -> Enum.at(fields, 8)
        _ -> nil
      end
    end)
  end

  @doc "Revokes the key `fpr_hex` in `homedir` by generating and importing a revocation certificate."
  @spec revoke_key!(Path.t(), String.t()) :: :ok
  def revoke_key!(homedir, fpr_hex) do
    cert = Path.join(homedir, "revoke_#{fpr_hex}.asc")
    answers = Path.join(homedir, "revoke_#{fpr_hex}.answers")
    File.write!(answers, "y\n0\n\ny\n")
    base = ["--homedir", homedir, "--yes", "--no-tty", "--command-file", answers]
    args = base ++ ["--output", cert, "--gen-revoke", fpr_hex]
    {_, 0} = System.cmd("gpg", args, stderr_to_stdout: true)

    {_, 0} =
      System.cmd("gpg", ["--homedir", homedir, "--batch", "--import", cert],
        stderr_to_stdout: true
      )

    :ok
  end

  @doc "A recipient-mode key for `fpr_hex` living in `homedir`."
  @spec recipient_key(Path.t(), String.t(), map()) :: Key.t()
  def recipient_key(homedir, fpr_hex, meta \\ %{}) do
    %Key{
      algorithm: :gpg,
      public: Base.decode16!(fpr_hex),
      metadata: Map.merge(%{homedir: homedir}, meta)
    }
  end

  @doc "A symmetric-mode key for `passphrase`."
  @spec symmetric_key(String.t(), map()) :: Key.t()
  def symmetric_key(passphrase, meta \\ %{}) do
    %Key{
      algorithm: :gpg,
      public: "label",
      private: passphrase,
      metadata: Map.merge(%{mode: :symmetric}, meta)
    }
  end

  @doc "Decrypts `ciphertext` with the stock gpg CLI against `homedir`."
  @spec shell_decrypt!(Path.t(), binary()) :: binary()
  def shell_decrypt!(homedir, ciphertext) do
    file = Path.join(homedir, "shell_decrypt_#{System.unique_integer([:positive])}")
    File.write!(file, ciphertext)
    {out, status} = System.cmd("gpg", ~w(--homedir #{homedir} --batch --quiet --decrypt #{file}))
    assert status == 0
    out
  end
end
