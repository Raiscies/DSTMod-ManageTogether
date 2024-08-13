
if GLOBAL then
    GLOBAL.setmetatable(GLOBAL, {__index = function(k, v)return GLOBAL.rawget(GLOBAL, k) end})
end


local RCoroutine = Class(function(self, fn)
    self.co = coroutine.create(fn)
end)

function RCoroutine:resume(...)
    local resume_result = {coroutine.resume(self.co, ...)}
    if not resume_result[1] then
        return nil
    else 
        return unpack(resume_result, 2)
    end   
end
function RCoroutine:__call(...)
    return self:resume(...)
end

local RCoroutineManager = Class(function(self)
    self.coro_list = {}
    self.uindex = 0

end)

function RCoroutineManager:Create(fn, name)
    self.uindex = self.uindex + 1
    
    if not name then
        name = 'RCoroutine(' .. tostring(self.uindex) .. ')'
    end
    local co = RCoroutine(fn)
    self.coro_list[smallhash(name)] = co
    return co, self.uindex
    
end
