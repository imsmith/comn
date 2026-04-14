conf = %{
    id: "be84723m50-4c3b-8f2a-9d1e2f3a4b5c",
    name: "example",
    version: "1.0.0",
    description: "An example configuration",
    schema: [:key1, :key2, :key3, :key4, :key5, ..., :keyN],
    tags: ["example", "demo"],
    backends: [ :ecto, :git, :ipfs ]
}

{:ok, token} = Comn.Repo.register(conf)

Comn.Repo.Table.set(token, %{key3: "value3"})
