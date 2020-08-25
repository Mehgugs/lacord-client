local cqs = require"cqueues"
local api = require"lacord.api"
local shard = require"lacord.shard"
local logger = require"lacord.util.logger"
local util = require"lacord.util"
local mutex = require"lacord.util.mutex"
local promise = require"cqueues.promise"
local signal = require"cqueues.signal"
local emitter = require"lacord.x.event"
local intents = require"lacord.util.intents"

util.capturable(api)

local traceback = debug.traceback
local xpcall = xpcall
local get = rawget
local setmetatable = setmetatable
local pairs = pairs
local assert = assert
local ipairs = ipairs
local _ENV = {}

__index = _ENV
__name = "lacord.x.adapter"

--- make wrapped coroutines report errors via a debug traceback
local old_wrap do
    old_wrap = cqs.interpose('wrap', function(self, ...)
        return old_wrap(self, function(fn, ...)
            local s, e = xpcall(fn, traceback, ...)
            if not s then
                logger.error(e)
            end
        end, ...)
    end)
end

--- Creates a new client, whuch is a collection of
local empty_options = {}
function new(token, options)
    options = options or empty_options
    local adapter = setmetatable({
        api = api.init{
            token = "Bot "..token
           ,precision = "millisecond"
           ,accept_encoding = true
           ,track_ratelimits = false
           ,route_delay = 0
        }
       ,shards = {}
       ,loop = cqs.new()
       ,identex = mutex.new()
       ,options = options
       ,events = { }
       ,receive = true
       ,ready = emitter.new'ready'
       ,has_ready = promise.new()
       ,intents = options.intents or (intents.guilds | intents.guild_messages)
       ,wsl = not not options.wsl
    }, _ENV)

    -- set up some important events
    adapter:new_event'MESSAGE_CREATE'
    adapter:new_received'READY'
    adapter:new_received'GUILD_CREATE'
    adapter:new_received'GUILD_DELETE'
    adapter:new_received'DISCONNECT'

    return adapter
end

function new_event(adapter, name)
    adapter.events[name] = emitter.new(name)
end

function new_received(adapter, name)
    adapter.events[name] = emitter.new(name):listen(adapter)
end

--- Factory for gateway urls containing token reset checks.
function refresher(adapter)
    local function regenerate_gateway(ws)
        local success , gateway, err = adapter.api:get_gateway_bot()
        assert(success, err)
        local limit = gateway.session_start_limit
        logger.info("TOKEN-%s has used %d/%d sessions.",
                util.hash(adapter.api.token),
                limit.total - limit.remaining,
                limit.total)

        if limit.remaining == 0 then
            logger.warn("TOKEN-%s can no longer identify, waiting for %.3f seconds",
                util.hash(adapter.api.token),
                limit.reset_after/1000)
            cqs.sleep(limit.reset_after/1000)
            return regenerate_gateway(ws)
        else
            return gateway.url
        end
    end
    return regenerate_gateway
end

--- A little object to hold discord events.
local context do
    local ctx_meta = {__name = "lacord.x.eventcontext"}
    function ctx_meta:__index(k)
        if k == 'shard_id' then return get(self, 1)
        elseif k == 'event' then return get(self, 2)
        end
    end
    function context(...)
        return setmetatable({...}, ctx_meta)
    end
end

--- Factory which produces an event handler for our client.
function eventer(adapter)
    return function(s, t, event)
        if adapter.events[t] then
            adapter.events[t]:enqueue(context(s.options.id, event))
        end
    end
end

--- Blocks sigterm and sigint to gracefully disconnect shards and then let cqueues drop off.
-- @TODO this breaks if you try to use the discord websocket (when i tried to null my voice state channel)
local function handlesignals(adapter)
    signal.block(signal.SIGINT, signal.SIGTERM)
    local sig = signal.listen(signal.SIGTERM, signal.SIGINT)
    local int = sig:wait()
    local reason = signal.strsignal(int)
    logger.info("%s received (%d, %q); shutting down.", adapter, int, reason)
    if not adapter.wsl then
        for _, s in pairs(adapter.shards) do
            s:shutdown()
        end
    end
    signal.unblock(signal.SIGINT, signal.SIGTERM)
end

--- Async function which gets our bot's information and then connects the shards.
local function runner(adapter)
    local R = adapter.api
        :capture(adapter.api:get_current_application_information())
        :get_gateway_bot()
    if R.success then
        local gatewayinfo
        adapter.app, gatewayinfo  = R:results()
        adapter.numshards = gatewayinfo.shards
        logger.info("starting %s with %d shards.", adapter, adapter.numshards)
        local output = adapter:eventer()
        local refresh = adapter:refresher()
        for i = 0 , gatewayinfo.shards - 1 do
            local s = shard.init({
                token = adapter.api.token
                ,id = i
                ,gateway = refresh
                ,compress = false
                ,transport_compression = true
                ,total_shard_count = gatewayinfo.shards
                ,large_threshold = 100
                ,auto_reconnect = true
                ,loop = cqs.running()
                ,output = output,
                intents = adapter.intents
            }, adapter.identex)
            adapter.shards[i] = s
            s:connect()
        end
        adapter.loop:wrap(handlesignals, adapter)
    else
        logger.error(R.error)
    end
end

function run(adapter)
    adapter.loop:wrap(runner, adapter)
    return assert(adapter.loop:loop())
end

function READY(adapter, ctx)
    adapter.guilds = adapter.guilds or {}
    for _, ug in ipairs(ctx.event.guilds) do
        if not adapter.guilds[ug.id] then
            adapter.guilds[ug.id] = promise.new()
        elseif adapter.guilds[ug.id]:status() ~= 'pending' then
            adapter.guilds[ug.id] = promise.new()
        end
    end
    adapter.ready:enqueue(ctx)
    adapter.has_ready:set(true)
end

function DISCONNECT(adapter, ctx)
    if adapter.has_ready:status() ~= 'pending' then
        adapter.has_ready = promise.new()
    end
end

function GUILD_CREATE(adapter, ctx)
    if promise.type(adapter.guilds[ctx.event.id]) then
        adapter.guilds[ctx.event.id]:set(true, ctx.event)
    else
        adapter.guilds[ctx.id] = promise.new()
        adapter.guilds[ctx.id]:set(true, ctx.event)
    end
end

function GUILD_DELETE(adapter, ctx)
    if ctx.event.unavailable then
        if promise.type(adapter.guilds[ctx.event.id])
        and adapter.guilds[ctx.event.id]:status() ~= 'pending' then
            adapter.guilds[ctx.event.id] = promise.new()
        end
    end
    adapter.guilds[ctx.event.id] = nil
end

function wait_guild(adapter, guild_id)
    if adapter.guilds[guild_id] then return adapter.guilds[guild_id]:get()
    else adapter.has_ready:get() return adapter.guilds[guild_id]:get() end
end

return _ENV