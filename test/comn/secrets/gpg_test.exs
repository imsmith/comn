defmodule Comn.Secrets.GPGTest do
  use ExUnit.Case
  @moduletag :gpg
  import Comn.Secrets.GPGHelpers

  setup do
    home = homedir!()
    fpr = gen_key!(home)
    {:ok, home: home, fpr: fpr, key: recipient_key(home, fpr)}
  end

  test "helper generates a usable key", %{home: home, fpr: fpr} do
    assert String.length(fpr) in [40, 64]
    assert Bitwise.band(File.stat!(home).mode, 0o777) == 0o700
  end
end
