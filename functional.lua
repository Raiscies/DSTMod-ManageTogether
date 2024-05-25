

if not _G then
    _G = GLOBAL
    
    GLOBAL.setmetatable(env, {__index = function(t, k) return GLOBAL.rawget(GLOBAL, k) end})
end

local unpack = table.unpack and table.unpack or _G.unpack

Functional = {}

Functional.category = {
    NORMAL = 0,
    UNARY_OPERATOR = 1, 
    BINARY_OPERATOR = 2
}

local Function, Parameter, ParameterFrom, is_functional_object, is_parameter_object

local function apply(f, ...)
    if type(f) == 'function' then
        return f(...)
    else
        assert(f ~= nil and type(f.fn) == 'function')
        return f.fn(...)
    end
end

local release_flag_meta = {}
function Functional.release(i, j)
    return setmetatable({i = i, j = j}, release_flag_meta)
end
local function is_release(o)
    return getmetatable(o) == release_flag_meta
end

local function params_apply(param, f)
    if not is_release(f) then
        return Parameter(apply(f, unpack(param.args)))
    else
        return unpack(param.args, f.i, f.j)
    end
end


local function partial(f, ...) 
    local outer_args = {...} 
    return Function(function(...) 
        return f(unpack(outer_args), ...) 
    end) 
end

function Functional.choose(i)
    return Function(function(...)
        local args = {...}
        return args[i]
    end)
end
function Functional.take(i, j)
    return Function(function(...)
        return unpack({...}, i, j or i) 
    end)
end
function Functional.iterate(fn)
    local result = {}
    return Function(function(iter)
        for v in iter do
            table.insert(result, fn(v))
        end
        return ParameterFrom(result)
    end)
end

-- placeholder
function Functional.hold(i)
    return {_placeholder_index = i}
end

local function placeholder_index(t)
    return t and t._placeholder_index
end

function Functional.bind(f, ...)
    local outer_args = {...} 
    return Function(function(...) 
        local inner_args = {...}
        local max_placeholder = 0
        for i, v in ipairs(outer_args) do
            if placeholder_index(v) then
                outer_args[i] = inner_args[placeholder_index(v)]
                max_placeholder = i
            end
        end
        return f(table.unpack(outer_args), select(max_placeholder + 1, ...)) 
    end) 
end

function Functional.mid(f)
    return Function(function(...)
        local args = {...}
        -- print(args[#args])
        -- print(unpack(args, 1, #args - 1))
        return f(args[#args], unpack(args, 1, #args - 1))
    end)
end

local FunctionMeta

local function Operator(op)
    return setmetatable({fn = op, operator = true}, FunctionMeta)
end

local function make_operator(fn, alias)
    return {
        fn = Operator(fn), 
        alias = alias,
    }
end

local function is_operator(fn)
    return type(fn) == 'table' and fn.operator == true
end

Functional.operator_map = {}
Functional.operator = {}

local operators = {
    make_operator(                            function(g) return Function(function(...) return         -   g(...) end) end     , {'NEG', 'neg', '-'} ),
    make_operator(                            function(g) return Function(function(...) return         not g(...) end) end     , {'NOT', 'not', '!'} ),
    make_operator(function(f) return Operator(function(g) return Function(function(...) return  f(...) and g(...) end) end) end, {'AND', 'and', '&'} ),
    make_operator(function(f) return Operator(function(g) return Function(function(...) return  f(...) or  g(...) end) end) end, {'OR' , 'or' , '|'} ),
    make_operator(function(f) return Operator(function(g) return Function(function(...) return  f(...) +   g(...) end) end) end, {'ADD', 'add', '+'} ),
    make_operator(function(f) return Operator(function(g) return Function(function(...) return  f(...) -   g(...) end) end) end, {'SUB', 'sub', '-'} ),
    make_operator(function(f) return Operator(function(g) return Function(function(...) return  f(...) *   g(...) end) end) end, {'MUL', 'mul', '*'} ),
    make_operator(function(f) return Operator(function(g) return Function(function(...) return  f(...) /   g(...) end) end) end, {'DIV', 'div', '/'} ),
    make_operator(function(f) return Operator(function(g) return Function(function(...) return  f(...) %   g(...) end) end) end, {'MOD', 'mod', '%'} ),
    make_operator(function(f) return Operator(function(g) return Function(function(...) return  f(...) ..  g(...) end) end) end, {'CON', 'con', '..'}),
}
for _, v in ipairs(operators) do
    for _, alias in ipairs(v.alias) do
        Functional.operator_map[alias] = v.fn
    end
    Functional.operator[v.alias[1]] = v.fn
end


local function pipline(f, g)
    -- local f_type = type(f)
    -- if f_type == 'string' then
    --     -- unary operator
    --     local operator = Functional.operator_map[f]
    --     assert(operator ~= nil)
    --     return operator.fn(g)
    -- elseif f_type == 'table' and f.is_operator then
    --     return f.fn(g)
    -- end


    if is_operator(f) then
        -- is unary operator, or the right hand side of a binary operator
        -- eg:        NOT * g
        --     (f1 * ADD) * g
        return f.fn(g)
    elseif is_operator(g) then
        -- is binary operator
        -- eg: f1 * AND * f2
        return g.fn(f)
    else
        -- simple pipline 
        return Function(
            function(...) 
                return g(f(...)) 
            end
        ) 
    end


    --   f * AND * g     1 = fn, 2 = op
    -- (f * ADD) * g     1 =   , 2 = fn
    --       NOT * g     1 = op, 2 = fn

    
    -- _ = param(12) - fuck(inrange) * SUB * fuck(print)

    -- if type(g) == 'string' then 
    --     -- binary operator: left hand side
    --     local operator = Functional.operator_map[g]
    --     assert(operator ~= nil)
    --     return operator.fn(f)
    -- elseif type(f) == 'table' and f.binary_partial then 
    --     -- binary operator: right hand side
    --     return Function(
    --         function(...)
    --             return f(g)(...)
    --         end
    --     )
    -- else
    --     return Function(
    --         function(...) 
    --             return g(f(...)) 
    --         end
    --     ) 
    -- end
end



FunctionMeta = {
    -- -- operator or
    -- __add = op_or,
    -- -- operator and
    -- __mul = op_and,
    -- -- operator not
    -- __unm = op_not, 

    __call = apply, 
    __index = partial, 
    -- __concat = pipline
    __mul = pipline,
}

local ParameterMeta = {
    __sub = params_apply
}

is_functional_object = function(f)
    return type(f) == 'table' and getmetatable(f) == FunctionMeta
end

is_parameter_object = function(p)
    return type(p) == 'table' and getmetatable(p) == ParameterMeta
end

Function = function(fn)
    return setmetatable({fn = fn}, FunctionMeta)
end
Parameter = function(...)
    return setmetatable({args = {...}}, ParameterMeta)
end
ParameterFrom = function(tab)
    if type(tab) ~= 'table' then
        tab = {tab}
    end
    return setmetatable({args = tab}, ParameterMeta)
end
Functional.fun   = Function
Functional.fuck  = Function
Functional.param = Parameter
Functional.from  = ParameterFrom
-- Functional.release = release
-- Functional.take = take
-- Functional.
-- Functional.mid   = mid
-- Functional.pl    = placeholder
-- Functional.

-- _ = puck('abc') - string.upper - (fuck(in_range)[12][100] + fuck(in_int_range)[-10][0])

-- puck(0) - (intable[tab] - 'or' - inrange[1][14])

--           let H(f, g)     equvalent to f - mid(H) - g
-- (checked) let H(f, g)     equvalent to f - 'op' - g
-- (checked) let fun(x, ...) equvalent to x - mid(fun)[...]
-- (checked) let f(x)        equvalent to pack(x) - f



-- -- let H(f, g, ...) equvalent to a - mid(H) [b](...)

-- import functions
function Functional.import(...)
    if select('#', ...) == 0 then
        for name, fn in pairs(Functional) do
            _G[name] = fn
        end
        -- import operator shortened names
        for name, op in pairs(Functional.operator) do
            _G[name] = op
        end
    else
        local targets = {...}
        for _, fn_name in ipairs(targets) do
            if Functional[fn_name] or Functional.builtin[fn_name] then
                _G[fn_name] = Functional[fn_name] or Functional.builtin[fn_name]
            end
        end

    end
end

-- debug.debug()
return Functional