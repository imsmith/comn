defmodule Comn.DoctestTest do
  use ExUnit.Case, async: false
  doctest Comn
  doctest Comn.Context
  doctest Comn.Contexts
  doctest Comn.Error
  doctest Comn.Errors.ErrorStruct
  doctest Comn.Errors
  doctest Comn.Event
  doctest Comn.EventBus
  doctest Comn.EventLog
  doctest Comn.Events.EventStruct
  doctest Comn.Events
  doctest Comn.Events.NATS
  doctest Comn.Events.Registry
  doctest Comn.Infra
  doctest Comn.Repo.Actor
  doctest Comn.Repo.Batch
  doctest Comn.Repo.Batch.Mem
  doctest Comn.Repo.Cmd
  doctest Comn.Repo.Cmd.Shell
  doctest Comn.Repo.Column.ETS
  doctest Comn.Repo.Column
  doctest Comn.Repo
  doctest Comn.Repo.File
  doctest Comn.Repo.File.IPFS
  doctest Comn.Repo.File.Local
  doctest Comn.Repo.File.NFS
  doctest Comn.Repo.Graphs
  doctest Comn.Repo.Stream
  doctest Comn.Repo.Table.ETS
  doctest Comn.Repo.Table
  doctest Comn.Secrets.Local
  doctest Comn.Secrets.Vault
end
