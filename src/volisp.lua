local conveniencemeta
local each = function(self, f)
  local revf = function (key, item) f(item, key) end
  table.foreach(self, revf)
  return self
end
local unpackit = function(self) return unpack(self) end
local map = function(self, f)
  local acc = setmetatable({}, conveniencemeta)
  self:each(function(item, key) acc[key] = f(item) end)
  return acc
end
local extend = function(self, other, override)  -- untested!
  other = convenience(other)
  local callback = override and function(item, key) if self[key] == nil then self[key] = item end end or function(item, key) self[key] = item end
  other:each(callback)
end
local slice = function(self, left, right)
  for i=#self,right+1,-1 do table.remove(self, i) end
  for i=1,left-1 do table.remove(self, 1) end
  return self
end
local reduce = function(self, f, base)
  if(base == nil) then base = table.remove(self, 1) end
  self:each(function (item, key) --print('base', base, item, key)
    base = f(base, item, key) end)
  return base
end
function apply(self)  -- self is a list of lists wrapped in convenience, every first element of a list is either a callable
  local acc = convenience()
  self:each(function(item)
     item = {unpack(item)}
     local f = table.remove(item, 1)
     assert(type(f) == 'function' or type(f) == 'table' and getmetatable(f).__call, 'the first argument must be callable')
     local result = convenience({f(unpack(item))})
     result:each(function (item) table.insert(acc, item) end)
  end)
  return acc
end
function concat(self, separator) return table.concat(self, separator) end
function relaytometa(self, key)
  local value = rawget(self, key)
  if value == nil
  then --print(key, getmetatable(self)[key])
    return getmetatable(self)[key]
  else return value end
end
conveniencemeta = { __index = relaytometa,
                    map = map,
                    reduce = reduce,
                    slice = slice,
                    apply = apply,
                    each = each,
                    concat = concat,
                    extend = extend,
                    unpack = unpackit }
function convenience(self)  -- either a table or a list of values
  if self == nil then self = {} end
  -- make a deep copy every time?!  -- only if we will have deep methods
  local shallowCopy = {}
  table.foreach(self, function (key, item) shallowCopy[key] = item end)
  return setmetatable(shallowCopy, conveniencemeta)
end

-- function runtree(tree, callback)
--   tree = convenience(tree)
--   tree:each(function(_, leaf)
--     if (type(leaf) == 'table')
--     then
--       if leaf.callable then callback('atom:', leaf.name) end
--       return runtree(leaf, callback)
--     else callback('val:', leaf) end
--   end)
-- end

-- (function(...)
--   local args = {...}
--   local acc = table.remove(args, 1)
--   for i=2,#args do acc = acc + args[i] end
--   print(acc)
-- end)(1, 2, 3, 4)

function buildvolisp()
  local operatortemplate = '(%s%s %s)'  -- this space is to prevent the commenting out of consequtive minus signs 
  function generateoperatortemplate(operatorstr)
    local template = operatortemplate:format('%s', operatorstr, '%s')
    return function(self, ...)
      local result = template
      local args = convenience({...}):apply()
      local argslen = #args
      result = convenience(args):slice(1, argslen-2):reduce(function (prev, next) return prev:format(next, template) end, result)
      result = result:format(args[argslen-1], args[argslen])
      return result
    end
  end
  local volisp = convenience({ add = '+', sub = '-', mul = '*', div = '/', mod = '%', pow = '^' }):map(generateoperatortemplate)
  volisp.set = function(self, symbols, ...)
    local symbols = convenience({symbols}):apply():concat(',')
    local values = convenience({...}):apply():concat(',')
    local template = '%s=%s'
    return template:format(symbols, values)
  end
  volisp.let = function(self, ...)
    local template = 'local %s'
    return template:format(volisp.set(...))
  end
  volisp.fn = function(self, params, ...)
    local args = {...}
    local _return = table.remove(args, #args)
    assert(_return[1] ~= volisp.let, 'cannot return the following expressions: let')
    _return = convenience({_return}):apply():concat(',')
    params = convenience({params}):apply():concat(',')
    local _body = convenience(args):apply():concat(' ')
    local template = 'function(%s) %s return %s end'
    return template:format(params, _body, _return)
  end
  volisp.sym = function(self, ...) return ... end
  volisp.lit = function(self, ...)
    local args = convenience({...})
    args = args:map(function (item)
      if type(item) == 'number' or type(item) == 'string'
      then return tostring(item)
      elseif type(item) == 'table' then --print(item[1].name)
        return convenience({item}):apply():concat(', ')
      else assert(false, 'the argument can only be either a number, a string or a table') end
    end)
    return args:unpack()
  end
  volisp.call = function(self, f, ...)
    f = convenience({f}):apply():concat(', ')
    args = convenience({...}):apply():concat(', ')
    local template = '%s(%s)'
    return template:format(f, args)
  end
  volisp:each(function(call, name)
      local meta = { __call = call, callable = true, name = name, __index = relaytometa }
      volisp[name] = setmetatable({}, meta)
    end)
  return volisp
end

local volisp = buildvolisp()
local set, let, fn, sym, lit, call, add, sub = volisp.set, volisp.let, volisp.fn, volisp.sym, volisp.lit, volisp.call, volisp.add, volisp.sub

--print('fun!', fn({ sym, 'x','y' }, {set, { sym, 'i' }, { lit, 6 }}, {let, { sym, 'z' }, { lit, 10 }, { sym, 'q' }, { fn, { sym, 'a' }, {let, { sym, 'o' }, { lit, '"tester"'}, {sym, 'ff'}, {fn, {sym}, {lit, 999}}}, { lit, 66 } }}, { add, {lit, 1, { sub, { lit, 2, -3 } }, 4, 5}}))
--print(convenience(1, 2, 3, 4, 5):reduce(function (x, y) return x*y end))
--print('fun222!', fn({ sym, 'x','y' }, {set, { sym, 'i' }, { lit, 6 }}, {let, { sym, 'z' }, { lit, 10 }, { sym, 'q' }, { fn, { sym, 'a' }, {let, { sym, 'o' }, { lit, '"tester"'}, {sym, 'ff'}, {fn, {sym}, {lit, 999}}}, { lit, 66 } }}, {lit, 111}))
print(call({sym, 'x'}, {lit, 'x', 'y'}))
print(fn({sym, 'f', 'x', 'y'}, {let, {sym, 'x', 'y', 'z'}, {lit, 888}, {call, {sym, 'f'}, {lit, 7, 8}}}, {add, {sym, 'x', 'y'}}))