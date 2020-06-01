package = 'lacord-client'
version = 'scm-0'

source = {
    url = 'git://github.com/Mehgugs/lacord-client.git'
}

local details = [[
Generic state container for lacord providing a higher level abstraction for making a discord bot.
]]

description = {
    summary = 'A generic client for lacord.'
    ,homepage = 'https://github.com/Mehgugs/lacord-client'
    ,license = 'MIT'
    ,maintainer = 'Magicks <m4gicks@gmail.com>'
    ,detailed = details
}

dependencies = {
     'lua >= 5.3'
    ,'lacord'
}

build = {
    type = "builtin"
    ,modules = {
        ["lacord.x.client"] = "lua/lacord-client/client.lua",
        ["lacord.x.event"] = "lua/lacord-client/event.lua",
        ["lacord.x.queue"] = "lua/lacord-client/queue.lua",
        ["lacord.x.timer"] = "lua/lacord-client/timer.lua"
    }
}