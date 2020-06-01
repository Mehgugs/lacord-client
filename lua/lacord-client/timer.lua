local cqueues = require"cqueues"
local poll = cqueues.poll

local monotime = cqueues.monotime
local setmetatable = setmetatable

local _ENV = {}

__index = _ENV
__name = "timer"

function new(whence)
    return setmetatable({
        deadline = whence+monotime(),
        duration = whence
    }, _ENV)
end

function timeout(timer)
    local left = timer.deadline - monotime()
    if left > 0 then
        return left
    end
end

function restart(timer)
    timer.deadline = timer.duration + monotime()
    return timer
end

function wait(timer, ...)
    return poll(timer, ...)
end

return _ENV