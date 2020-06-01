[lacord]: https://github.com/Mehgugs/lacord

# Lacord Client

> A generic state container for lacord providing a higher level abstraction for making a discord bot.

## About

This library provides a tiny abstraction over [lacord] to make using the library a bit easier.
Instead of dealing directly with shards, a top level client is provided to contain all shard state and the api state. A channel like system is used to relay events from discord to the client (a much richer feature than
the single callback lacord shards use).

## Modules provided

- `lacord.x.client` For creating a client.
- `lacord.x.event` For creating event channels.

## Small example
```lua
local new_client = require"lacord.x.client".new
local bot = new_client(os.getenv"TOKEN")

bot.events.MESSAGE_CREATE:listen(function(ctx)
    local msg = ctx.event
    if not msg.author.bot and msg.content == "TEST" then
        bot.api:create_message(msg.channel_id, {
            content = "Hello, world! 🌚"
        })
    end
end)

bot:run()
```

