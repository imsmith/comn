ExUnit.start()

# Start the Registry that EventBus depends on
{:ok, _} = Registry.start_link(keys: :duplicate, name: Comn.EventBus)
