local queue = require"moonlava.queue"
local cqueues = require"cqueues"
local cond = require"cqueues.condition"
local promise = require"cqueues.promise"
local setmetatable = setmetatable
local _running = cqueues.running
local type = type
local assert = assert
local monotime = cqueues.monotime
local error = error
local pairs = pairs
local _ENV = {}

__index = _ENV
__name = "moonlava.emitter"

local function running(em)
    return _running() or em.loop
end

--- Makes a new emitter.
function new(tag)
    return setmetatable({
          cbs = queue.new()
         ,pollfd = cond.new()
         ,waiting = 0
         ,tag = tag or false
    }, _ENV)
end

-- Listen to the event.
function listen(em, ...)
    em.cbs:pushes_right(...)
    return em
end

--- Listen to event but will execute before :listen.
function listen_first(em, ...)
    em.cbs:pushes_left(...)
    return em
end

-- Emit the event.
function emit(em, event)
    for _, cb in em.cbs:from_left() do
        if type(cb) == 'function' then
            cb(event)
        elseif cb.receive then
            if em.tag then
                cb[em.tag](cb, event)
            else
                cb:receive(event)
            end
        elseif cb.emit then
            cb:emit(event)
        end
    end
    em._last = event
    em.pollfd:signal()
    return em
end

-- Emit the event without blocking.
function enqueue(em, event)
    for _, cb in em.cbs:from_left() do
        if type(cb) == 'function' then
            running(em):wrap(cb,event)
        elseif cb.receive then
            if em.tag then
                if not cb[em.tag] then return error(("%s is missing tagged event %s"):format(cb, em.tag)) end
                running(em):wrap(cb[em.tag], cb, event)
            else
                running(em):wrap(cb.receive, cb, event)
            end
        elseif cb.enqueue then
            cb:enqueue(event)
        end
    end
    em._last = event
    return em.pollfd:signal()
end

local function not_eq(a,b) return a ~= b end

--- Removes an listener by value.
function remove(em, cb)
    em.cbs = em.cbs:filtered(not_eq, cb)
end

--- Waits for the next event optionally within a given timeout.
function wait(em, ...)
    em.waiting = em.waiting + 1
    local recd = em.pollfd:wait(...)
    local ev

    if recd then
        ev = em._last
        if em.waiting == 1 then
            em._last = nil
        end
    end
    em.waiting = em.waiting - 1
    return ev, not recd
end

local function waiter(em, ...)
    em.waiting = em.waiting + 1
    local recd = em.pollfd:wait(...)
    local ev

    if recd then
        ev = em._last
        if em.waiting == 1 then
            em._last = nil
        end
    else
        return error("emitter rejected")
    end
    em.waiting = em.waiting - 1
    return ev
end

--- Returns a promise that will resolve when the next event is emitted.
function promised (em, ...)
    return promise.new(waiter, em, ...)
end


local function collect_backlog(state)
    while state.in_body and not state.done do
        local ev = state.em:wait()
        state.backlog:push_left(ev)
    end
end

local function iter_inf(state)
    state.in_body = false
    if state.done then return nil end
    if state.backlog.length > 0 then
        state.in_body = true
        running(state.em):wrap(collect_backlog, state)
        return state, state.backlog:pop_right()
    else
        local result = state.em:wait()
        state.in_body = true
        running(state.em):wrap(collect_backlog, state)
        return state, result
    end
end

local function collect_waiting(state)
    local result, timedout
    if state.em.cancelfd then
        result, timedout = state.em:wait(state.em.cancelfd, state.deadline - monotime())
    else
        result, timedout = state.em:wait(state.deadline - monotime())
    end
    if timedout or monotime() >= state.deadline then state.done = true return nil end
    return result
end

local function iter(state)
    state.in_body = false
    if state.done then return nil end
    if state.backlog.length > 0 then
        state.in_body = true
        if monotime() < state.deadline then running(state.em):wrap(collect_backlog, state) end
        return state, state.backlog:pop_right()
    else
        local res = collect_waiting(state)
        if res then
            state.in_body = true
            running(state.em):wrap(collect_backlog, state)
            return state, res
        end
    end
end


--- Iterator for events.
function __pairs(em, timeout)
    if timeout then
        return iter, {done = false, em = em, deadline = monotime() + timeout, in_body = false, backlog = queue.new()}
    else
        return iter_inf, {done = false, em = em, in_body = false, backlog = queue.new()}
    end
end

--- Predicated wait, which can optionally accept a timeout.
-- The timeout is global for the request and not a timeout for each event.
-- It *must* be a timeout unlike wait which can accept any number of pollables.
function await(em, f, timeout)
    assert(f, "Please provide a filter to await. To wait for an event with no filtering use emitter:wait().")
    if timeout then
        local deadline = (monotime() + timeout)
        repeat
            local e, timedout = em:wait(deadline - monotime())
            if not timedout and f(e) then return e
            elseif timedout then return nil, true end
        until monotime() >= deadline
        return nil, true
    else
        local e
        repeat
            e = em:wait()
        until f(e)
        return e
    end
end

function awaitn(em, n, f, timeout)
    assert(f, "Please provide a filter to await. To wait for an event with no filtering use emitter:wait().")
    if timeout then
        local deadline = (monotime() + timeout)
        local results = {}
        repeat
            local e, timedout = em:wait(deadline - monotime())
            if not timedout and f(e) then
                insert(results, e)
            elseif timedout then return results, true end
        until monotime() >= deadline or #results == n
        return results, #results ~= #n
    else
        local results = {}
        repeat
            insert(results, (em:wait()))
        until #results == n
        return results
    end
end

function cancellable(em)
    em.cancelfd = cond.new()
    return em
end

--- Cancel an emitter, causing any subscriptions it has to finish.
function cancel(em)
    em.cancelfd:signal()
    return em
end

function map(em, f, out)
    out = out or new()
    local function listener(e)
        return out:emit(f(e))
    end
    em:listen(listener)
    return out, listener
end

function filter(em, f, out)
    out = out or new()
    local function listener(e)
        if f(e) then out:emit(e) end
    end
    em:listen(listener)
    return out, listener
end

function reduce(em, f, a, out)
    out = out or new()
    local function listener(e)
        a = f(a, e)
        out:emit(a)
    end
    em:listen(listener)
    return out, listener
end

function enmap(em, f, out)
    out = out or new()
    local function listener(e)
        return out:enqueue(f(e))
    end
    em:listen(listener)
    return out, listener
end

function enfilter(em, f, out)
    out = out or new()
    local function listener(e)
        if f(e) then out:enqueue(e) end
    end
    em:listen(listener)
    return out, listener
end

function enreduce(em, f, a, out)
    out = out or new()
    local function listener(e)
        a = f(a, e)
        out:enqueue(a)
    end
    em:listen(listener)
    return out, listener
end

function transform(em, f, out)
    out = out or new()
    local function listener(e)
        local res = f(e)
        if res ~= nil then
            return out:emit(res)
        end
    end
    em:listen(listener)
    return out, listener
end

function entransform(em, f, out)
    out = out or new()
    local function listener(e)
        local res = f(e)
        if res ~= nil then
            return out:enqueue(res)
        end
    end
    em:listen(listener)
    return out, listener
end

function split(em, f, set)
    local function listener(e)
        local piv = f(e)
        if piv and set[piv] then
            set[piv]:emit(e)
        end
    end
    em:listen(listener)
    return listener
end

function ensplit(em, f, set)
    local function listener(e)
        local piv = f(e)
        if piv and set[piv] then
            set[piv]:enqueue(e)
        end
    end
    em:listen(listener)
    return listener
end



return _ENV