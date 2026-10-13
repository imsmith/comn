defmodule Comn.Test.SessionRow do
  @moduledoc false
  # A consumer-owned Ecto schema for the Table :ecto backend tests. Comn
  # converges the "sessions" table to this declaration on first use and
  # upserts event data into it. :count is an integer so a bad value makes
  # the saga fail.
  use Ecto.Schema

  @primary_key {:id, :string, autogenerate: false}
  schema "sessions" do
    field(:user, :string)
    field(:count, :integer)
  end
end

defmodule Comn.Test.BrokenRow do
  @moduledoc false
  # Declares the same "sessions" table as SessionRow with a column it does
  # not have, so an upsert through it fails inside the database.
  use Ecto.Schema

  @primary_key {:id, :string, autogenerate: false}
  schema "sessions" do
    field(:user, :string)
    field(:extra, :string)
  end
end

defmodule Comn.Test.Repo do
  @moduledoc false
  # A consumer-owned repo, for the `repo:` form of the :ecto backend.
  use Ecto.Repo, otp_app: :comn, adapter: Ecto.Adapters.SQLite3
end
