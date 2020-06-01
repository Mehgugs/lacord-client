--- Simple double-ended queue from lua examples.
-- @module util.queue
-- @alias _ENV

--imports--
local setmetatable = setmetatable
local insert, ipairs = table.insert, ipairs
local max = math.max
--start-module--
local _ENV = {}

--- Doubled ended queue.
-- @table queue
-- @within Objects
-- @see queue.new
-- @field first The first item.
-- @field last  The last item.
-- All functions which take a queue as their first argument can be called from the queue in method form.

--- Constructs a new `queue`.
-- @treturn queue
function new()
    return setmetatable({
         _first = 0
        ,_last = -1
        ,parity = true
    }, _ENV)
end

--- Concatenates two lists into a queue.
-- @param t1 The first list.
-- @param t2 The second list.
-- @treturn queue
function cat(t1, t2)
  local q = new()
  local len = max(#t1, #t2)
  for i = len, 1, -1 do
    local j = len+1-i
    local i1 = t1[i]
    local i2 = t2[j]
    if i1 ~= nil then
      q:push_left(i1)
    end
    if i2 ~= nil then
      q:push_right(i2)
    end
  end
  return q
end

--- Pushes a value onto the front of the queue.
-- @tparam queue list The queue.
-- @param value The value to push.
-- @treturn queue
function push_left(list, value)
    local first = list._first - 1
    list._first = first
    list[first] = value
    return list
end

--- Pushes a value onto the back of the queue.
-- @tparam queue list The queue.
-- @param value The value to push.
-- @treturn queue
function push_right(list, value)
    local last = list._last + 1
        list._last = last
        list[last] = value
    return list
end

--- Pushes multiple values to the front of the queue.
-- Call this with a vararg.
-- @tparam queue list The queue.
-- @param a The first item in the vararg.
-- @param[opt] ... Additional values.
-- @usage
--  d = queue.new():pushes_left(1,2,3)
--  for _, value in d:from_right() do
--      print(value)
--  end --> 1
--      --> 2
--      --> 3
local function lpushes_left(list, a, ...)
    if a ~= nil then
        return lpushes_left(list:push_left(a), ...)
    else return list end
end
pushes_left = lpushes_left

--- Pushes multiple values to the back of the queue.
-- Call this with a vararg.
-- @tparam queue list The queue.
-- @param a The first item in the vararg.
-- @param[opt] ... Additional values.
-- @usage
--  d = queue.new():pushes_right(1,2,3)
--  for _, value in d:from_left() do
--      print(value)
--  end --> 1
--      --> 2
--      --> 3
local function lpushes_right(list, a, ...)
    if a ~= nil then
        return lpushes_right(list:push_right(a), ...)
    else return list end
end
pushes_right = lpushes_right

--- Pops a value from the front of the queue.
-- @tparam queue list The queue.
-- @treturn queue
function pop_left(list)
    local first = list._first
    if first > list._last then return nil end
    local value = list[first]
    list[first] = nil
    list._first = first + 1
    return value
end

--- Pops a value from the back of the queue.
-- @tparam queue list The queue.
-- @treturn queue
function pop_right(list)
    local last = list._last
    if list._first > last then return nil end
    local value = list[last]
    list[last] = nil
    list._last = last - 1
    return value
end

function lpeek_left(list, places)
    places = places or 0
    return places >= 0
        and list[list._first + places]
        or  list:peek_right(-places)
end

function lpeek_right(list, places)
    places = places or 0
    return places >= 0
        and list[list._last - places]
        or  list:peek_left(-places)
end

local function iter_left(list, state)
    if state < list._last then
        return state + 1, list[state+1]
    end
end

local function iter_right(list, state)
    if state > list._first then
        return state - 1, list[state-1]
    end
end

--- Left-handed iterator over the queue.
-- @tparam queue list The queue to iterate over.
-- @return idx Index in list.
-- @return value The value.
-- @usage
--  d = queue.new():pushes_right(1,2,3)
--  for idx, value in d:from_left() do
--      print(value)
--  end --> 1
--      --> 2
--      --> 3
function from_left(list)
    return iter_left, list, list._first -1
end

--- Right-handed iterator over the queue.
-- @tparam queue list The queue to iterate over.
-- @return idx Index in list.
-- @return value The value.
-- @usage
--  d = queue.new():pushes_right(1,2,3)
--  for idx, value in d:from_left() do
--      print(value)
--  end --> 3
--      --> 2
--      --> 1
function from_right(list)
    return iter_right, list, list._last +1
end

--- Iterates over a queue from left to right, consuming the values.
-- @tparam queue list The queue to iterate over.
-- @return value The consumed value.
-- @usage
--  d = queue.new():pushes_right(1,2,3)
--  print(#d, d.first) --> 3, 1
--  for value in d:consume_left() do
--      ..
--  end
--  print(#d, d.first) --> 0, nil
function consume_left(list)
    return pop_left, list
end

--- Iterates over a queue from right to left, consuming the values.
-- @tparam queue list The queue to iterate over.
-- @return value The consumed value.
-- @usage
--  d = queue.new():pushes_right(1,2,3)
--  print(#d, d.first) --> 3, 1
--  for value in d:consume_right() do
--      ..
--  end
--  print(#d, d.first) --> 0, nil
function consume_right(list)
    return pop_right, list
end

--- Filters a queue in-place, from left to right.
-- @tparam queue list The queue to filter.
-- @func f The predicate function.
-- @param[opt] ... Optional arguments to `f`.
-- @treturn queue
-- @usage
--  q = queue.new():pushes_right(1, 2, 3, 4, 5, 6, 7, 8, 9)
--  q:filter(function(x) return x % 2 == 0 end)
--  for _, v in q:from_left() do print(v) end
--  --> 2
--  --> 4
--  --> 6
--  --> 8
function filter(list, f, ...)
    local count = 0
    for i = list._first, list._last do
        if f(list[i], ...) then
            list:push_right(list[i])
            count = count + 1
        end
        list[i] = nil
    end
    list._first = list._last - count +1
    return list
end

--- Filters a queue out of place, returning a new queue, from left to right.
--  @tparam queue list The queue to filter.
--  @tparam function f The predicate function.
--  @param[opt] ... Optional arguments to `f`.
--  @treturn queue The new queue containing the results.
function filtered(list, f, ...)
    local out = new()
    for _, v in list:from_left() do
       if f(v, ...) then out:push_right(v) end
    end
    return out
end

--- Transforms a queue in place, from left to right.
--  @tparam queue list The list to transform.
--  @tparam function m The mapping function.
--  @param[opt] ... Optional arguments to `m`.
--  @treturn queue
--  @usage
--   q = queue.new():pushes_right(1,2,3,4,5)
--   q:map(function(x) return x*x end)
--   for _, v in q:from_left() do print(v) end
--   --> 1
--   --> 4
--   --> 9
--   --> 16
--   --> 25
function map(list, m,...)
    for i = list._first, list._last do
        list[i] = m(list[i], ...)
    end
    return list
end

--- Transforms a queue out of place, returning a new queue, from left to right.
--  See @{util.list.map} for mapping examples.
--  @tparam queue list The list to transform.
--  @tparam function m The mapping function.
--  @param[opt] ... Optional arguments to `m`.
--  @treturn queue
--  @tparam queue list The list to transform
function mapped(list, m, ...)
    local out = new()
    for _, v in list:from_left() do out:push_right(m(v, ...)) end
    return out
end

--- Returns a plain table array containing the elements of the queue.
--  This operates from left to right.
--  @tparam queue list The queue.
--  @treturn table An array of the elements.
function to_table(list)
    local out = {}
    for _, v in ipairs(list) do
        insert(out, v)
    end
    return out
end


function __index(list, key)
    if key == 'first' then
        return list[list._first]
    elseif key == 'last' then
        return list[list._last]
    else
        return _ENV[key]
    end
end

--- Length of the queue.
-- @tparam queue list The queue.
-- @treturn number
-- @usage
--  d = queue.new():pushes_left(1,2):pushes_right(3,4)
--  #d --> 4
function __len(list)
    return  list._last - list._first +1
end

--- `ipairs` iterator.
--  Returns `from_left`
--  @tparam queue list The queue.
--  @usage
--   for _, item in ipairs(queue) do
--     ..
--   end
function __ipairs(list)
    if list.parity then
        return from_left(list)
    else
        return from_right(list)
    end
end

--end-module--
return _ENV
